#include "record/record.h"
#include "recorder_dispatcher.h"
#include "test/fake_capture_engine.h"
#include "test/recorder_test_support.h"

#include <gtest/gtest.h>

#include <memory>

namespace record_windows
{
	// Drives the recorder with a fake engine that fails on demand and needs no device.
	class RecorderReattachTest : public ::testing::Test
	{
	protected:
		void SetUp() override
		{
			m_dispatcher = std::make_shared<RecorderDispatcher>();
		}

		void TearDown() override
		{
			if (m_recorder)
			{
				Call(*m_dispatcher, [this] { return m_recorder->Dispose(); });
				m_recorder.reset();
			}
		}

		void StartTake(AudioRouteChange mode, std::string deviceId = "")
		{
			RecorderCallbacks callbacks;
			// Called on the dispatcher, where the tests read it too.
			callbacks.onConfigChanged = [this](const RecordConfig& config) {
				m_reportedDeviceIds.push_back(config.deviceId);
			};

			m_recorder = std::make_unique<Recorder>(m_dispatcher, std::move(callbacks),
				[this](std::shared_ptr<RecorderDispatcher>, ICaptureEngine::SampleHandler)
					-> std::unique_ptr<ICaptureEngine> {
					auto engine = std::make_unique<FakeCaptureEngine>();
					m_fake = engine.get();
					return engine;
				});

			ASSERT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this, mode, deviceId] {
				auto config = MakeConfig(AudioEncoder::pcm16bits, mode);
				config->deviceId = deviceId;
				return m_recorder->StartStream(std::move(config));
			}));
			ASSERT_TRUE(IsRecording());

			// Only what happens after the start counts.
			Call(*m_dispatcher, [this] { m_reportedDeviceIds.clear(); return 0; });
		}

		std::vector<std::string> ReportedDeviceIds()
		{
			return Call(*m_dispatcher, [this] { return m_reportedDeviceIds; });
		}

		void FailOpens(int count)
		{
			Call(*m_dispatcher, [this, count] { m_fake->FailOpens(count); return 0; });
		}

		void FailStarts(int count)
		{
			Call(*m_dispatcher, [this, count] { m_fake->FailStarts(count); return 0; });
		}

		HRESULT Resume()
		{
			return Call(*m_dispatcher, [this] { return m_recorder->Resume(); });
		}

		// The take itself opens once: everything after that is a reattach.
		int ReattachOpens()
		{
			return Call(*m_dispatcher, [this] {
				return static_cast<int>(m_fake->OpenedDeviceIds().size()) - 1;
			});
		}

		void LoseRoute()
		{
			Call(*m_dispatcher, [this] { m_recorder->OnRouteLost(); return 0; });
		}

		// What the device watch posts, after the reader may have handled the loss already.
		void ReportDeviceLost(std::string deviceId)
		{
			Call(*m_dispatcher, [this, deviceId] { m_recorder->OnDeviceLost(deviceId); return 0; });
		}

		void ChangeDefaultDevice(std::string deviceId)
		{
			Call(*m_dispatcher, [this, deviceId] {
				m_fake->SetDefaultDeviceId(deviceId);
				m_recorder->OnDefaultInputChanged();
				return 0;
			});
		}

		void SetDefaultDeviceId(std::string deviceId)
		{
			Call(*m_dispatcher, [this, deviceId] { m_fake->SetDefaultDeviceId(deviceId); return 0; });
		}

		std::string LastOpenedDeviceId()
		{
			return Call(*m_dispatcher, [this] { return m_fake->OpenedDeviceIds().back(); });
		}

		bool IsOpen() { return Call(*m_dispatcher, [this] { return m_fake->IsOpen(); }); }

		bool IsRecording() { return Call(*m_dispatcher, [this] { return m_recorder->IsRecording(); }); }
		bool IsPaused()    { return Call(*m_dispatcher, [this] { return m_recorder->IsPaused(); }); }

		std::shared_ptr<RecorderDispatcher> m_dispatcher;
		std::unique_ptr<Recorder> m_recorder;
		FakeCaptureEngine* m_fake = nullptr;
		std::vector<std::string> m_reportedDeviceIds;
	};

	// Nothing left to record with: the take waits instead of ending.
	TEST_F(RecorderReattachTest, FollowPausesWhenNoDeviceOpens)
	{
		StartTake(AudioRouteChange::follow);
		FailOpens(99);

		LoseRoute();

		EXPECT_TRUE(IsPaused());
		EXPECT_FALSE(IsRecording());
	}

	// No retry on a timer: the take waits for Resume().
	TEST_F(RecorderReattachTest, FollowTriesOnceThenWaits)
	{
		StartTake(AudioRouteChange::follow);
		FailOpens(99);

		LoseRoute();

		EXPECT_EQ(ReattachOpens(), 1);
	}

	// Dart reads an empty deviceId as the default device.
	TEST_F(RecorderReattachTest, FollowReportsTheDefaultDevice)
	{
		StartTake(AudioRouteChange::follow, "usb-mic");

		LoseRoute();

		EXPECT_EQ(ReportedDeviceIds(), std::vector<std::string>{ "" });
	}

	TEST_F(RecorderReattachTest, FollowFromTheDefaultDeviceReportsNothing)
	{
		StartTake(AudioRouteChange::follow);

		LoseRoute();

		EXPECT_TRUE(ReportedDeviceIds().empty());
	}

	TEST_F(RecorderReattachTest, AFailedFollowReportsNothing)
	{
		StartTake(AudioRouteChange::follow, "usb-mic");
		FailOpens(99);

		LoseRoute();

		EXPECT_TRUE(ReportedDeviceIds().empty());
	}

	TEST_F(RecorderReattachTest, AResumeOnTheDefaultDeviceReportsTheMove)
	{
		StartTake(AudioRouteChange::pause, "usb-mic");
		LoseRoute();
		// The selected device is still gone.
		FailOpens(1);

		ASSERT_HRESULT_SUCCEEDED(Resume());

		EXPECT_EQ(LastOpenedDeviceId(), "default-device");
		EXPECT_EQ(ReportedDeviceIds(), std::vector<std::string>{ "" });
	}

	// Pause mode lets the user plug their device back in.
	TEST_F(RecorderReattachTest, AResumeReopensTheSelectedDeviceWhenItIsBack)
	{
		StartTake(AudioRouteChange::pause, "usb-mic");
		LoseRoute();

		ASSERT_HRESULT_SUCCEEDED(Resume());

		EXPECT_EQ(LastOpenedDeviceId(), "usb-mic");
		EXPECT_TRUE(ReportedDeviceIds().empty());
	}

	// The lost device's source starts fine and only fails on its first read.
	TEST_F(RecorderReattachTest, AResumeAfterALossOpensADeviceAgain)
	{
		StartTake(AudioRouteChange::pause);
		LoseRoute();

		ASSERT_HRESULT_SUCCEEDED(Resume());

		EXPECT_EQ(ReattachOpens(), 1);
	}

	// The reader and the device watch both report one unplug.
	TEST_F(RecorderReattachTest, ASecondReportOfTheSameLossChangesNothing)
	{
		StartTake(AudioRouteChange::follow);
		FailOpens(1);
		LoseRoute();

		LoseRoute();

		EXPECT_EQ(ReattachOpens(), 1);
		EXPECT_TRUE(IsPaused());
	}

	// Left open, the next Resume() would restart it with nothing watching it.
	TEST_F(RecorderReattachTest, AHalfDoneMoveClosesTheDevice)
	{
		StartTake(AudioRouteChange::follow);
		ASSERT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this] { return m_recorder->Pause(); }));
		FailStarts(1);

		LoseRoute();

		EXPECT_FALSE(IsOpen());
		EXPECT_HRESULT_SUCCEEDED(Resume());
		EXPECT_TRUE(IsOpen());
	}

	// Once on the default device, later moves change nothing Dart can see.
	TEST_F(RecorderReattachTest, ReportsTheMoveOnlyOnce)
	{
		StartTake(AudioRouteChange::follow, "usb-mic");

		LoseRoute();
		LoseRoute();

		EXPECT_EQ(ReportedDeviceIds().size(), 1u);
	}

	// Caps, capture and the device watch all get the same, resolved device.
	TEST_F(RecorderReattachTest, TakeOpensTheResolvedDefaultDevice)
	{
		StartTake(AudioRouteChange::follow);

		EXPECT_EQ(LastOpenedDeviceId(), "default-device");
	}

	// Whatever the take opened, a reattach asks for the default device.
	TEST_F(RecorderReattachTest, ReattachOpensTheDefaultDevice)
	{
		StartTake(AudioRouteChange::follow);
		Call(*m_dispatcher, [this] { m_fake->SetDefaultDeviceId("other-device"); return 0; });

		LoseRoute();

		EXPECT_EQ(LastOpenedDeviceId(), "other-device");
	}

	// Pause mode holds the take where it is, without hunting for a device.
	TEST_F(RecorderReattachTest, PauseModeDoesNotReattach)
	{
		StartTake(AudioRouteChange::pause);

		LoseRoute();

		EXPECT_TRUE(IsPaused());
		EXPECT_EQ(ReattachOpens(), 0);
	}

	// The take is not lost: a device that opens again takes over.
	TEST_F(RecorderReattachTest, ResumeOpensADeviceAfterAFailedFollow)
	{
		StartTake(AudioRouteChange::follow);
		FailOpens(99);
		LoseRoute();
		ASSERT_TRUE(IsPaused());

		FailOpens(0);

		EXPECT_HRESULT_SUCCEEDED(Resume());
		EXPECT_TRUE(Call(*m_dispatcher, [this] { return m_fake->IsOpen(); }));
	}

	// Dart raises RecordResumeNoDeviceException on this code alone.
	TEST_F(RecorderReattachTest, ResumeReportsNoInputDeviceWhenNoneIsLeft)
	{
		StartTake(AudioRouteChange::follow);
		SetDefaultDeviceId("");
		LoseRoute();
		ASSERT_TRUE(IsPaused());

		EXPECT_EQ(Resume(), E_RECORD_NO_INPUT_DEVICE);
	}

	// A device is there but won't open: the app must see why, not "no device".
	TEST_F(RecorderReattachTest, ResumeReturnsTheOpenError)
	{
		StartTake(AudioRouteChange::follow);
		FailOpens(99);
		LoseRoute();
		ASSERT_TRUE(IsPaused());

		EXPECT_EQ(Resume(), E_FAIL);
		EXPECT_TRUE(IsPaused());
	}

	// The reader moved the take first: the watch's report of the old device must not move it again.
	TEST_F(RecorderReattachTest, IgnoresALossReportForADeviceAlreadyLeft)
	{
		StartTake(AudioRouteChange::follow);
		SetDefaultDeviceId("other-device");
		LoseRoute();

		ReportDeviceLost("default-device");

		EXPECT_EQ(ReattachOpens(), 1);
	}

	TEST_F(RecorderReattachTest, FollowsALossReportForTheDeviceInUse)
	{
		StartTake(AudioRouteChange::follow);
		SetDefaultDeviceId("other-device");
		LoseRoute();
		SetDefaultDeviceId("third-device");

		ReportDeviceLost("other-device");

		EXPECT_EQ(LastOpenedDeviceId(), "third-device");
	}

	// A late read from the dead source would otherwise end the take.
	TEST_F(RecorderReattachTest, PauseModeClosesTheLostDevice)
	{
		StartTake(AudioRouteChange::pause);

		LoseRoute();

		EXPECT_FALSE(IsOpen());
		EXPECT_HRESULT_SUCCEEDED(Resume());
		EXPECT_TRUE(IsOpen());
	}

	TEST_F(RecorderReattachTest, PauseModeClosesTheLostDeviceAfterAUserPause)
	{
		StartTake(AudioRouteChange::pause);
		ASSERT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this] { return m_recorder->Pause(); }));

		LoseRoute();

		EXPECT_FALSE(IsOpen());
		EXPECT_TRUE(IsPaused());
	}

	// Windows may still name the lost device as default when the loss is handled.
	TEST_F(RecorderReattachTest, FollowMovesToTheNextDefaultDevice)
	{
		StartTake(AudioRouteChange::follow);
		FailOpens(1);
		LoseRoute();
		ASSERT_TRUE(IsPaused());

		ChangeDefaultDevice("other-device");

		EXPECT_EQ(LastOpenedDeviceId(), "other-device");
		EXPECT_TRUE(IsOpen());
		// The move ended the route-loss pause: a later default changes nothing.
		ChangeDefaultDevice("third-device");
		EXPECT_EQ(ReattachOpens(), 2);
	}

	TEST_F(RecorderReattachTest, FollowKeepsWaitingWhenTheNextDefaultFails)
	{
		StartTake(AudioRouteChange::follow);
		FailOpens(2);
		LoseRoute();

		ChangeDefaultDevice("other-device");

		EXPECT_FALSE(IsOpen());
		EXPECT_TRUE(IsPaused());
		EXPECT_HRESULT_SUCCEEDED(Resume());
	}

	// Only Resume() ends a pause the user asked for.
	TEST_F(RecorderReattachTest, ANewDefaultKeepsAUserPause)
	{
		StartTake(AudioRouteChange::follow);
		ASSERT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this] { return m_recorder->Pause(); }));
		FailOpens(1);
		LoseRoute();

		ChangeDefaultDevice("other-device");

		EXPECT_EQ(ReattachOpens(), 1);
	}

	TEST_F(RecorderReattachTest, ANewDefaultKeepsAPauseAskedDuringTheLoss)
	{
		StartTake(AudioRouteChange::follow);
		FailOpens(1);
		LoseRoute();
		ASSERT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this] { return m_recorder->Pause(); }));

		ChangeDefaultDevice("other-device");

		EXPECT_EQ(ReattachOpens(), 1);
	}

	TEST_F(RecorderReattachTest, ANewDefaultLeavesAPauseModeTake)
	{
		StartTake(AudioRouteChange::pause);
		LoseRoute();

		ChangeDefaultDevice("other-device");

		EXPECT_EQ(ReattachOpens(), 0);
		EXPECT_TRUE(IsPaused());
	}

	// Follow moves only off a lost device, not to every new default.
	TEST_F(RecorderReattachTest, ANewDefaultLeavesARecordingTake)
	{
		StartTake(AudioRouteChange::follow);

		ChangeDefaultDevice("other-device");

		EXPECT_EQ(ReattachOpens(), 0);
	}

	// A user pause resumes on its own device, so Resume() returns that device's error, not E_RECORD_NO_INPUT_DEVICE.
	TEST_F(RecorderReattachTest, ResumeFailsLoudlyAfterAUserPause)
	{
		StartTake(AudioRouteChange::follow);
		ASSERT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this] { return m_recorder->Pause(); }));
		FailStarts(1);

		EXPECT_EQ(Resume(), E_FAIL);
		EXPECT_EQ(ReattachOpens(), 0);
	}
}
