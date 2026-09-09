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
}
