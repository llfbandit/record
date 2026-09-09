#include "record/reader_callback.h"

#include <gtest/gtest.h>
#include <mfapi.h>
#include <mferror.h>

#include <atomic>
#include <future>
#include <memory>
#include <thread>

namespace record_windows
{
	namespace
	{
		void Flush(RecorderDispatcher& dispatcher)
		{
			std::promise<void> done;
			auto ran = done.get_future();
			if (!dispatcher.Post([&done] { done.set_value(); })) return;
			ran.wait();
		}

		ULONG RefCount(IUnknown* unknown)
		{
			unknown->AddRef();
			return unknown->Release();
		}
	}

	class ReaderCallbackTest : public ::testing::Test
	{
	protected:
		void SetUp() override { ASSERT_HRESULT_SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET)); }
		void TearDown() override { MFShutdown(); }
	};

	TEST_F(ReaderCallbackTest, DeliversSamplesOnTheDispatcherThread)
	{
		auto dispatcher = std::make_shared<RecorderDispatcher>();
		std::thread::id handlerThread;
		HRESULT seenStatus = E_FAIL;
		LONGLONG seenTimestamp = 0;
		IMFSample* seenSample = nullptr;

		auto* callback = new ReaderCallback(dispatcher,
			[&](HRESULT hr, DWORD, LONGLONG timestamp, IMFSample* sample) {
				handlerThread = std::this_thread::get_id();
				seenStatus = hr;
				seenTimestamp = timestamp;
				seenSample = sample;
			});

		IMFSample* sample = nullptr;
		ASSERT_HRESULT_SUCCEEDED(MFCreateSample(&sample));

		callback->OnReadSample(S_OK, 0, 0, 123, sample);
		Flush(*dispatcher);

		EXPECT_NE(handlerThread, std::this_thread::get_id());
		EXPECT_EQ(seenStatus, S_OK);
		EXPECT_EQ(seenTimestamp, 123);
		EXPECT_EQ(seenSample, sample);
		// Only the test's reference is left: the task dropped the one MF's callback took.
		EXPECT_EQ(RefCount(sample), 1u);

		sample->Release();
		callback->Release();
	}

	// EndRecording disarms so a released reader's last samples cannot land in the next take.
	TEST_F(ReaderCallbackTest, DropsSamplesAfterDisarm)
	{
		auto dispatcher = std::make_shared<RecorderDispatcher>();
		std::atomic<int> handled{ 0 };

		auto* callback = new ReaderCallback(dispatcher,
			[&handled](HRESULT, DWORD, LONGLONG, IMFSample*) { handled++; });

		// Disarm belongs to the dispatcher thread, where EndRecording runs.
		dispatcher->Post([callback] { callback->Disarm(); });

		IMFSample* sample = nullptr;
		ASSERT_HRESULT_SUCCEEDED(MFCreateSample(&sample));

		callback->OnReadSample(S_OK, 0, 0, 0, sample);
		Flush(*dispatcher);

		EXPECT_EQ(handled.load(), 0);
		EXPECT_EQ(RefCount(sample), 1u);

		sample->Release();
		callback->Release();
	}

	// MF can deliver after the recorder is gone; a refused task must still let go.
	TEST_F(ReaderCallbackTest, ReleasesSamplesTheDispatcherRefuses)
	{
		auto dispatcher = std::make_shared<RecorderDispatcher>();
		dispatcher->Shutdown();
		dispatcher->Join();

		auto* callback = new ReaderCallback(dispatcher,
			[](HRESULT, DWORD, LONGLONG, IMFSample*) { FAIL() << "handler ran after shutdown"; });

		IMFSample* sample = nullptr;
		ASSERT_HRESULT_SUCCEEDED(MFCreateSample(&sample));

		callback->OnReadSample(S_OK, 0, 0, 0, sample);

		EXPECT_EQ(RefCount(sample), 1u);
		EXPECT_EQ(RefCount(callback), 1u);

		sample->Release();
		callback->Release();
	}

	// A failed status carries no sample to forward, but still reaches the recorder.
	TEST_F(ReaderCallbackTest, DeliversFailuresWithoutASample)
	{
		auto dispatcher = std::make_shared<RecorderDispatcher>();
		HRESULT seenStatus = S_OK;
		std::atomic<int> handled{ 0 };

		auto* callback = new ReaderCallback(dispatcher,
			[&](HRESULT hr, DWORD, LONGLONG, IMFSample*) {
				seenStatus = hr;
				handled++;
			});

		callback->OnReadSample(MF_E_INVALIDREQUEST, 0, 0, 0, nullptr);
		Flush(*dispatcher);

		EXPECT_EQ(handled.load(), 1);
		EXPECT_EQ(seenStatus, MF_E_INVALIDREQUEST);

		callback->Release();
	}
}
