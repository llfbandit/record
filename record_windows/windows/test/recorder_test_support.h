#pragma once

#include <windows.h>

#include <future>
#include <memory>

#include "audio_device/record_audio_device.h"
#include "record_config.h"
#include "recorder_dispatcher.h"

namespace record_windows
{
	// Recorder methods assert they run on the dispatcher, so hop and wait.
	template <typename F>
	auto Call(RecorderDispatcher& dispatcher, F f) -> decltype(f())
	{
		std::promise<decltype(f())> done;
		auto value = done.get_future();
		dispatcher.Post([&done, f]() mutable { done.set_value(f()); });
		return value.get();
	}

	// Tests that record for real skip themselves without a capture device.
	inline bool HasCaptureDevice()
	{
		CoInitializeEx(nullptr, COINIT_MULTITHREADED);
		flutter::EncodableList devices;
		HRESULT hr = AudioDevice::ListInputDevices(devices);
		CoUninitialize();

		return SUCCEEDED(hr) && !devices.empty();
	}

	// Mono keeps a take small.
	inline std::unique_ptr<RecordConfig> MakeConfig(const char* encoder, AudioRouteChange mode)
	{
		return std::make_unique<RecordConfig>(
			encoder, "", 128000, 44100, 1, false, false, false, mode,
			flutter::EncodableMap());
	}
}
