#include "recorder_wrapper.h"

#include <gtest/gtest.h>

namespace record_windows
{
	namespace
	{
		// Channels need a messenger; no engine is running here.
		class FakeMessenger : public flutter::BinaryMessenger
		{
		public:
			void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply) const override {}
			void SetMessageHandler(const std::string&, flutter::BinaryMessageHandler) override {}
		};

		struct SinkLog
		{
			int successes = 0;
			int ends = 0;
		};

		class FakeEventSink : public flutter::EventSink<flutter::EncodableValue>
		{
		public:
			explicit FakeEventSink(SinkLog& log) : m_log(log) {}

		protected:
			void SuccessInternal(const flutter::EncodableValue*) override { m_log.successes++; }
			void ErrorInternal(const std::string&, const std::string&, const flutter::EncodableValue*) override {}
			void EndOfStreamInternal() override { m_log.ends++; }

		private:
			SinkLog& m_log;
		};

		void PumpUntil(const bool& flag)
		{
			for (int i = 0; i < 2000 && !flag; i++)
			{
				MSG msg;
				while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) DispatchMessage(&msg);
				if (!flag) Sleep(1);
			}
		}
	}

	TEST(RecorderWrapperTest, DisposeAnswersOnThePlatformThread)
	{
		FakeMessenger messenger;
		PlatformThread platform;
		RecorderWrapper wrapper(&messenger, "probe", platform);

		bool answered = false;
		wrapper.Dispose([&answered] { answered = true; });

		PumpUntil(answered);
		EXPECT_TRUE(answered);
	}

	TEST(EventStreamHandlerTest, EndOfStreamEndsDartStreamOnce)
	{
		SinkLog log;
		EventStreamHandler<> handler;
		handler.OnListen(nullptr, std::make_unique<FakeEventSink>(log));

		handler.EndOfStream();
		// A chunk or end after the stream ended goes nowhere.
		handler.Success(std::make_unique<flutter::EncodableValue>(1));
		handler.EndOfStream();

		EXPECT_EQ(log.ends, 1);
		EXPECT_EQ(log.successes, 0);
	}
}
