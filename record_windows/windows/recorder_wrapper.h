#pragma once

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>

#include <functional>
#include <map>
#include <memory>
#include <string>

#include "event_stream_handler.h"
#include "platform_thread.h"
#include "record/record.h"
#include "recorder_dispatcher.h"

namespace record_windows
{
	// One recorder: calls run on its dispatcher, replies land on the platform thread.
	class RecorderWrapper
	{
	public:
		RecorderWrapper(flutter::BinaryMessenger* messenger, const std::string& recorderId, PlatformThread& platform);
		~RecorderWrapper();

		using Reply = std::function<void(HRESULT)>;

		void Start(std::unique_ptr<RecordConfig> config, std::wstring path, Reply reply);
		void StartStream(std::unique_ptr<RecordConfig> config, Reply reply);
		void Pause(Reply reply);
		void Resume(Reply reply);
		void Stop(std::function<void(StopResult)> reply);
		void Cancel(Reply reply);
		void IsPaused(std::function<void(bool)> reply);
		void IsRecording(std::function<void(bool)> reply);
		void GetAmplitude(std::function<void(std::map<std::string, double>)> reply);
		// Answers once torn down; the wrapper may be destroyed from the reply.
		void Dispose(std::function<void()> reply);

	private:
		template <typename R, typename F>
		void Run(std::function<void(R)> reply, R fallback, F&& block);
		void Teardown(std::function<void()> done);

		PlatformThread& m_platform;
		// Cleared on destruction: event hops still queued on the platform thread must skip.
		std::shared_ptr<bool> m_alive = std::make_shared<bool>(true);

		EventStreamHandler<>* m_stateEventHandler;
		EventStreamHandler<>* m_recordEventHandler;
		std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> m_stateEventChannel;
		std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> m_recordEventChannel;
		std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> m_configChangedChannel;

		std::shared_ptr<RecorderDispatcher> m_dispatcher;
		std::unique_ptr<Recorder> m_recorder;
	};
}
