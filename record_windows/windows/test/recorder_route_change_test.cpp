#include "record/record.h"
#include "recorder_dispatcher.h"
#include "test/recorder_test_support.h"

#include <gtest/gtest.h>

#include <algorithm>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace record_windows
{
	// Records for real and only simulates the device removal.
	class RecorderRouteChangeTest : public ::testing::Test
	{
	protected:
		void SetUp() override
		{
			if (!HasCaptureDevice()) GTEST_SKIP() << "no capture device";

			wchar_t temp[MAX_PATH];
			GetTempPathW(MAX_PATH, temp);
			m_path = std::wstring(temp) + L"record_route_change_test.wav";

			m_dispatcher = std::make_shared<RecorderDispatcher>();
		}

		void TearDown() override
		{
			if (m_recorder)
			{
				Call(*m_dispatcher, [this] { return m_recorder->Dispose(); });
				m_recorder.reset();
			}
			if (!m_path.empty()) DeleteFileW(m_path.c_str());
		}

		void StartTake(AudioRouteChange mode)
		{
			RecorderCallbacks callbacks;
			callbacks.onState = [this](RecordState state) {
				std::lock_guard<std::mutex> lock(m_mutex);
				m_states.push_back(state);
			};

			m_recorder = std::make_unique<Recorder>(m_dispatcher, std::move(callbacks));

			ASSERT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this, mode] {
				return m_recorder->Start(MakeConfig(AudioEncoder::wav, mode), m_path);
			}));

			// Waits for some samples, so the take holds data.
			Sleep(1000);
			ASSERT_TRUE(Call(*m_dispatcher, [this] { return m_recorder->IsRecording(); }));
		}

		// Streams instead of writing a file, to count the incoming samples.
		void StartStreamTake(AudioRouteChange mode, std::function<void()> onChunk)
		{
			RecorderCallbacks callbacks;
			callbacks.onState = [this](RecordState state) {
				std::lock_guard<std::mutex> lock(m_mutex);
				m_states.push_back(state);
			};
			callbacks.onChunk = [onChunk](std::vector<uint8_t>) { onChunk(); };

			m_recorder = std::make_unique<Recorder>(m_dispatcher, std::move(callbacks));

			ASSERT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this, mode] {
				return m_recorder->StartStream(MakeConfig(AudioEncoder::pcm16bits, mode));
			}));

			Sleep(1000);
			ASSERT_TRUE(Call(*m_dispatcher, [this] { return m_recorder->IsRecording(); }));
		}

		// Same entry point as a real device removal.
		void LoseRoute()
		{
			Call(*m_dispatcher, [this] { m_recorder->OnRouteLost(); return 0; });
		}

		bool IsRecording() { return Call(*m_dispatcher, [this] { return m_recorder->IsRecording(); }); }
		bool IsPaused()    { return Call(*m_dispatcher, [this] { return m_recorder->IsPaused(); }); }

		std::vector<RecordState> States()
		{
			std::lock_guard<std::mutex> lock(m_mutex);
			return m_states;
		}

		int CountState(RecordState state)
		{
			auto states = States();
			return static_cast<int>(std::count(states.begin(), states.end(), state));
		}

		std::shared_ptr<RecorderDispatcher> m_dispatcher;
		std::unique_ptr<Recorder> m_recorder;
		std::wstring m_path;
		std::mutex m_mutex;
		std::vector<RecordState> m_states;
	};

	TEST_F(RecorderRouteChangeTest, StopModeEndsTheTake)
	{
		StartTake(AudioRouteChange::stop);

		LoseRoute();

		EXPECT_FALSE(IsRecording());
		EXPECT_FALSE(IsPaused());
		EXPECT_EQ(States().back(), RecordState::stop);
		// Stop keeps what was recorded before the loss.
		EXPECT_NE(GetFileAttributesW(m_path.c_str()), INVALID_FILE_ATTRIBUTES);
	}

	TEST_F(RecorderRouteChangeTest, PauseModeHoldsTheTake)
	{
		StartTake(AudioRouteChange::pause);

		LoseRoute();

		EXPECT_TRUE(IsPaused());
		EXPECT_EQ(States().back(), RecordState::pause);
	}

	// The take is not lost: it can go on with another device.
	TEST_F(RecorderRouteChangeTest, PauseModeResumesOnTheDefaultDevice)
	{
		StartTake(AudioRouteChange::pause);
		LoseRoute();
		ASSERT_TRUE(IsPaused());

		EXPECT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this] { return m_recorder->Resume(); }));

		Sleep(1000);
		EXPECT_TRUE(IsRecording());

		StopResult stopped = Call(*m_dispatcher, [this] { return m_recorder->Stop(); });
		EXPECT_HRESULT_SUCCEEDED(stopped.hr);
		EXPECT_FALSE(stopped.path.empty());
	}

	TEST_F(RecorderRouteChangeTest, FollowModeKeepsRecording)
	{
		StartTake(AudioRouteChange::follow);

		LoseRoute();

		Sleep(1000);
		EXPECT_TRUE(IsRecording());
		// A failed reattach would end up paused.
		EXPECT_EQ(CountState(RecordState::pause), 0);
		// The recorder doesn't report record again on the new device.
		EXPECT_EQ(CountState(RecordState::record), 1);

		StopResult stopped = Call(*m_dispatcher, [this] { return m_recorder->Stop(); });
		EXPECT_HRESULT_SUCCEEDED(stopped.hr);
		EXPECT_FALSE(stopped.path.empty());
	}

	// Samples must keep coming from the new device, not just the record state.
	TEST_F(RecorderRouteChangeTest, FollowModeKeepsDeliveringSamples)
	{
		std::atomic<int> chunks{ 0 };
		StartStreamTake(AudioRouteChange::follow, [&chunks] { chunks++; });
		ASSERT_GT(chunks.load(), 0);

		LoseRoute();

		// Counts only what comes after the swap.
		chunks = 0;
		Sleep(1000);

		EXPECT_GT(chunks.load(), 0);
	}

	// A device opened while paused has no read yet: Resume() must ask for a sample.
	TEST_F(RecorderRouteChangeTest, FollowModeDeliversSamplesAfterAPausedReattach)
	{
		std::atomic<int> chunks{ 0 };
		StartStreamTake(AudioRouteChange::follow, [&chunks] { chunks++; });

		ASSERT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this] { return m_recorder->Pause(); }));
		ASSERT_TRUE(IsPaused());

		LoseRoute();
		ASSERT_TRUE(IsPaused());

		// Counts only what comes after the resume.
		chunks = 0;
		ASSERT_HRESULT_SUCCEEDED(Call(*m_dispatcher, [this] { return m_recorder->Resume(); }));
		Sleep(1000);

		EXPECT_TRUE(IsRecording());
		EXPECT_GT(chunks.load(), 0);
	}

	TEST_F(RecorderRouteChangeTest, FollowModeHandlesASecondLoss)
	{
		StartTake(AudioRouteChange::follow);

		LoseRoute();
		Sleep(500);
		LoseRoute();
		Sleep(500);

		EXPECT_TRUE(IsRecording());
		EXPECT_EQ(CountState(RecordState::pause), 0);
	}
}
