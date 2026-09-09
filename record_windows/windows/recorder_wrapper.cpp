#include "recorder_wrapper.h"

#include <flutter/standard_method_codec.h>

using namespace flutter;

namespace record_windows
{
	RecorderWrapper::RecorderWrapper(BinaryMessenger* messenger, const std::string& recorderId, PlatformThread& platform)
		: m_platform(platform),
		m_dispatcher(std::make_shared<RecorderDispatcher>())
	{
		m_stateEventHandler = new EventStreamHandler<>();
		m_stateEventChannel = std::make_unique<EventChannel<EncodableValue>>(
			messenger, "com.llfbandit.record/events/" + recorderId,
			&StandardMethodCodec::GetInstance());
		m_stateEventChannel->SetStreamHandler(
			std::unique_ptr<StreamHandler<EncodableValue>>(m_stateEventHandler));

		m_recordEventHandler = new EventStreamHandler<>();
		m_recordEventChannel = std::make_unique<EventChannel<EncodableValue>>(
			messenger, "com.llfbandit.record/eventsRecord/" + recorderId,
			&StandardMethodCodec::GetInstance());
		m_recordEventChannel->SetStreamHandler(
			std::unique_ptr<StreamHandler<EncodableValue>>(m_recordEventHandler));

		m_configChangedChannel = std::make_unique<MethodChannel<EncodableValue>>(
			messenger, "com.llfbandit.record/configChanged/" + recorderId,
			&StandardMethodCodec::GetInstance());

		auto alive = m_alive;
		auto* stateHandler = m_stateEventHandler;
		auto* recordHandler = m_recordEventHandler;
		auto* configChannel = m_configChangedChannel.get();

		RecorderCallbacks callbacks;
		callbacks.onState = [this, alive, stateHandler](RecordState state) {
			m_platform.Post([alive, stateHandler, state] {
				if (*alive) stateHandler->Success(std::make_unique<EncodableValue>(state));
			});
		};
		callbacks.onChunk = [this, alive, recordHandler](std::vector<uint8_t> bytes) {
			m_platform.Post([alive, recordHandler, b = std::move(bytes)]() mutable {
				if (*alive) recordHandler->Success(std::make_unique<EncodableValue>(std::move(b)));
			});
		};
		callbacks.onConfigChanged = [this, alive, configChannel](const RecordConfig& cfg) {
			EncodableMap args = cfg.rawArgs;
			args[EncodableValue("bitRate")]     = EncodableValue(cfg.bitRate);
			args[EncodableValue("sampleRate")]  = EncodableValue(cfg.sampleRate);
			args[EncodableValue("numChannels")] = EncodableValue(cfg.numChannels);
			m_platform.Post([alive, configChannel, args = std::move(args)]() mutable {
				if (*alive) configChannel->InvokeMethod("onConfigChanged",
					std::make_unique<EncodableValue>(EncodableMap(std::move(args))));
			});
		};

		m_recorder = std::make_unique<Recorder>(m_dispatcher, std::move(callbacks));
	}

	RecorderWrapper::~RecorderWrapper()
	{
		Teardown(nullptr);
		m_dispatcher->Join();
		*m_alive = false;
	}

	// Tears down on the recorder's thread; a no-op once that already happened.
	void RecorderWrapper::Teardown(std::function<void()> done)
	{
		bool posted = m_dispatcher->Post([this, done] {
			m_recorder->Dispose();
			// Answered once the thread has stopped, so the join that follows never waits.
			std::function<void()> onExit;
			if (done) onExit = [this, done] { m_platform.Post(done); };
			m_dispatcher->Shutdown(std::move(onExit));
		});
		// Already disposed: still answer so the Dart future settles.
		if (!posted && done) m_platform.Post(done);
	}

	// Runs block on the dispatcher; its value reaches reply on the platform thread.
	template <typename R, typename F>
	void RecorderWrapper::Run(std::function<void(R)> reply, R fallback, F&& block)
	{
		bool posted = m_dispatcher->Post([this, reply, block = std::forward<F>(block)]() mutable {
			R value = block();
			m_platform.Post([reply, value] { reply(value); });
		});
		if (!posted) m_platform.Post([reply, fallback] { reply(fallback); });
	}

	void RecorderWrapper::Start(std::unique_ptr<RecordConfig> config, std::wstring path, Reply reply)
	{
		Run(std::move(reply), E_ABORT, [this, config = std::move(config), path]() mutable {
			return m_recorder->Start(std::move(config), path);
		});
	}

	void RecorderWrapper::StartStream(std::unique_ptr<RecordConfig> config, Reply reply)
	{
		Run(std::move(reply), E_ABORT, [this, config = std::move(config)]() mutable {
			return m_recorder->StartStream(std::move(config));
		});
	}

	void RecorderWrapper::Pause(Reply reply)
	{
		Run(std::move(reply), E_ABORT, [this] { return m_recorder->Pause(); });
	}

	void RecorderWrapper::Resume(Reply reply)
	{
		Run(std::move(reply), E_ABORT, [this] { return m_recorder->Resume(); });
	}

	void RecorderWrapper::Stop(std::function<void(StopResult)> reply)
	{
		Run(std::move(reply), StopResult{ E_ABORT, std::wstring() }, [this] { return m_recorder->Stop(); });
	}

	void RecorderWrapper::Cancel(Reply reply)
	{
		Run(std::move(reply), E_ABORT, [this] { return m_recorder->Cancel(); });
	}

	void RecorderWrapper::IsPaused(std::function<void(bool)> reply)
	{
		Run(std::move(reply), false, [this] { return m_recorder->IsPaused(); });
	}

	void RecorderWrapper::IsRecording(std::function<void(bool)> reply)
	{
		Run(std::move(reply), false, [this] { return m_recorder->IsRecording(); });
	}

	void RecorderWrapper::GetAmplitude(std::function<void(std::map<std::string, double>)> reply)
	{
		Run(std::move(reply), std::map<std::string, double>(), [this] { return m_recorder->GetAmplitude(); });
	}

	void RecorderWrapper::Dispose(std::function<void()> reply)
	{
		auto alive = m_alive;
		Teardown([this, alive, reply] {
			// Not in the destructor: at engine shutdown the messenger is already detached.
			if (*alive)
			{
				m_stateEventChannel->SetStreamHandler(nullptr);
				m_recordEventChannel->SetStreamHandler(nullptr);
			}
			reply();
		});
	}
}
