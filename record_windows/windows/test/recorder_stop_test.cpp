#include "record/record.h"
#include "audio_device/record_audio_device.h"
#include "recorder_dispatcher.h"

#include <gtest/gtest.h>

#include <fstream>
#include <future>
#include <iterator>
#include <memory>
#include <string>
#include <vector>

namespace record_windows
{
	namespace
	{
		// A take is only playable if the RIFF and data sizes match the file.
		void ExpectValidWavHeader(const std::wstring& path)
		{
			std::ifstream file(path.c_str(), std::ios::binary);
			ASSERT_TRUE(file.is_open());

			std::vector<uint8_t> bytes(
				(std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
			ASSERT_GT(bytes.size(), 12u);

			auto u32 = [&bytes](size_t at) {
				uint32_t value = 0;
				memcpy(&value, bytes.data() + at, sizeof(value));
				return value;
			};

			ASSERT_EQ(memcmp(bytes.data(), "RIFF", 4), 0);
			ASSERT_EQ(memcmp(bytes.data() + 8, "WAVE", 4), 0);
			EXPECT_EQ(u32(4), bytes.size() - 8);

			// Walk to the data chunk, whose size is written the same way.
			size_t offset = 12;
			while (offset + 8 <= bytes.size())
			{
				const uint32_t chunkSize = u32(offset + 4);
				if (memcmp(bytes.data() + offset, "data", 4) == 0)
				{
					EXPECT_EQ(chunkSize, bytes.size() - offset - 8);
					EXPECT_GT(chunkSize, 0u);
					return;
				}
				offset += 8 + chunkSize + (chunkSize & 1);
			}

			ADD_FAILURE() << "no data chunk";
		}

		// Recorder methods assert they run on the dispatcher, so hop and wait.
		template <typename F>
		auto Call(RecorderDispatcher& dispatcher, F f) -> decltype(f())
		{
			std::promise<decltype(f())> done;
			auto value = done.get_future();
			dispatcher.Post([&done, f]() mutable { done.set_value(f()); });
			return value.get();
		}

		bool HasCaptureDevice()
		{
			CoInitializeEx(nullptr, COINIT_MULTITHREADED);
			flutter::EncodableList devices;
			HRESULT hr = AudioDevice::ListInputDevices(devices);
			CoUninitialize();
			return SUCCEEDED(hr) && !devices.empty();
		}

		std::unique_ptr<RecordConfig> WavConfig()
		{
			return std::make_unique<RecordConfig>(
				AudioEncoder::wav, "", 128000, 44100, 1, false, false, false,
				flutter::EncodableMap());
		}
	}

	// A take that wrote data must stop cleanly; MF teardown order used to leak
	// MF_E_SHUTDOWN out of Stop().
	TEST(RecorderStopTest, StopSucceedsAfterARealTake)
	{
		if (!HasCaptureDevice()) GTEST_SKIP() << "no capture device";

		wchar_t temp[MAX_PATH];
		GetTempPathW(MAX_PATH, temp);
		std::wstring path = std::wstring(temp) + L"record_stop_test.wav";

		auto dispatcher = std::make_shared<RecorderDispatcher>();

		std::atomic<int> states{ 0 };
		RecorderCallbacks callbacks;
		callbacks.onState = [&states](RecordState) { states++; };
		Recorder recorder(dispatcher, std::move(callbacks));

		HRESULT started = Call(*dispatcher, [&] {
			return recorder.Start(WavConfig(), path);
		});
		ASSERT_HRESULT_SUCCEEDED(started);

		Sleep(3000);
		EXPECT_TRUE(Call(*dispatcher, [&] { return recorder.IsRecording(); }));

		StopResult stopped = Call(*dispatcher, [&] { return recorder.Stop(); });
		EXPECT_HRESULT_SUCCEEDED(stopped.hr);
		EXPECT_FALSE(stopped.path.empty());
		ExpectValidWavHeader(path);

		Call(*dispatcher, [&] { return recorder.Dispose(); });
		DeleteFileW(path.c_str());
	}
}
