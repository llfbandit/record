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
	TEST_F(RecorderReattachTest, ResumeReportsNoInputDeviceWhenNothingOpens)
	{
		StartTake(AudioRouteChange::follow);
		FailOpens(99);
		LoseRoute();
		ASSERT_TRUE(IsPaused());

		EXPECT_EQ(Resume(), E_RECORD_NO_INPUT_DEVICE);
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
