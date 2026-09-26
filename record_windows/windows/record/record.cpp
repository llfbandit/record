#include "record/record.h"
#include "audio_device/record_audio_device.h"
#include "record/sink/file_sink.h"
#include "record/sink/stream_sink.h"
#include "utils.h"

namespace record_windows
{
	Recorder::Recorder(std::shared_ptr<RecorderDispatcher> dispatcher, RecorderCallbacks callbacks,
		CaptureEngineFactory makeEngine)
		: m_dispatcher(std::move(dispatcher)),
		m_callbacks(std::move(callbacks))
	{
		m_engine = makeEngine(m_dispatcher,
			[this](HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample) {
				OnSample(hrStatus, dwStreamIndex, llTimestamp, pSample);
			});

		// The client starts with one reference, so Attach() it rather than add another.
		m_pRouteWatch.Attach(new DeviceNotificationClient());
	}

	Recorder::~Recorder()
	{
		// Dispose() already closed it on the dispatcher, unless it never ran.
		m_pRouteWatch->Close();
	}

	HRESULT Recorder::Start(std::unique_ptr<RecordConfig> config, std::wstring path)
	{
		AssertOnDispatcher();
		if (m_disposed) return E_ABORT;

		bool supported = false;
		HRESULT hr = AudioDevice::IsEncoderSupported(config->encoderName, &supported);

		if (FAILED(hr) || !supported)
		{
			return E_NOTIMPL;
		}

		return BeginTake(std::move(config), std::make_unique<FileSink>(std::move(path)));
	}

	HRESULT Recorder::StartStream(std::unique_ptr<RecordConfig> config)
	{
		AssertOnDispatcher();
		if (m_disposed) return E_ABORT;

		if (!StreamSink::Supports(config->encoderName))
		{
			return E_NOTIMPL;
		}

		return BeginTake(std::move(config), std::make_unique<StreamSink>(m_callbacks.onChunk));
	}

	HRESULT Recorder::BeginTake(std::unique_ptr<RecordConfig> config, std::unique_ptr<IRecordSink> sink)
	{
		HRESULT hr = OpenCaptureDevice(std::move(config));

		if (SUCCEEDED(hr))
		{
			Microsoft::WRL::ComPtr<IMFMediaType> pInputType;
			hr = m_engine->GetInputType(&pInputType);

			if (SUCCEEDED(hr))
			{
				hr = sink->Open(*m_pConfig, pInputType.Get());
			}
			if (SUCCEEDED(hr))
			{
				m_pSink = std::move(sink);
			}
		}
		if (SUCCEEDED(hr))
		{
			// Request the first sample
			hr = m_engine->RequestSample();
		}
		if (SUCCEEDED(hr))
		{
			UpdateState(RecordState::record);
		}
		else
		{
			EndRecording();
		}

		return hr;
	}

	HRESULT Recorder::OpenCaptureDevice(std::unique_ptr<RecordConfig> config)
	{
		HRESULT hr = EndRecording();

		// Resolve it once so caps, capture and the device watch see the same device.
		std::string deviceId;
		if (SUCCEEDED(hr))
		{
			hr = ResolveDevice(config->deviceId, deviceId);
		}

		if (SUCCEEDED(hr))
		{
			const int origSampleRate  = config->sampleRate;
			const int origNumChannels = config->numChannels;
			const int origBitRate     = config->bitRate;
			AudioDevice::AdjustConfigToDeviceCaps(*config, deviceId);
			hr = AudioDevice::AdjustConfigToCodecCaps(*config);
			if (SUCCEEDED(hr) && m_callbacks.onConfigChanged &&
				(config->sampleRate  != origSampleRate ||
				 config->numChannels != origNumChannels ||
				 config->bitRate     != origBitRate))
			{
				m_callbacks.onConfigChanged(*config);
			}
		}
		if (SUCCEEDED(hr))
		{
			m_pConfig = std::move(config);
		}

		if (SUCCEEDED(hr))
		{
			hr = m_engine->Open(*m_pConfig, deviceId);
		}
		if (SUCCEEDED(hr))
		{
			const uint64_t takeId = ++m_takeId;

			// Windows calls it on its notification thread; the dispatcher stops before this recorder dies.
			auto onRouteLost = [this, takeId, dispatcher = m_dispatcher]() {
				// A report this late may belong to a take that already ended.
				dispatcher->Post([this, takeId] {
					if (takeId == m_takeId) OnRouteLost();
				});
			};

			// Keep recording even when route changes can't be watched.
			HRESULT hrNotif = m_pRouteWatch->Start(Utf16FromUtf8(deviceId), onRouteLost);

			if (FAILED(hrNotif))
			{
				printf("Record: Unable to watch device removal (0x%X)\n", hrNotif);
			}
		}

		return hr;
	}

	void Recorder::OnRouteLost()
	{
		AssertOnDispatcher();

		if (m_disposed || !m_pConfig || m_recordState == RecordState::stop) return;

		// The reader and the device watch may both report the same loss.
		if (m_pausedByRouteLoss) return;
		m_pRouteWatch->Disarm();

		switch (m_pConfig->audioRouteChange)
		{
		case AudioRouteChange::follow:
		{
			// m_pausedByRouteLoss is false here, so any pause came from the user.
			const bool keepPaused = IsPaused();
			// When no device opens, hold the take until Resume() moves it.
			if (FAILED(MoveToDefaultDevice(keepPaused))) PauseForRouteLoss();
			break;
		}

		case AudioRouteChange::stop:
			Stop();
			break;

		default:
			PauseForRouteLoss();
			break;
		}
	}

	void Recorder::PauseForRouteLoss()
	{
		// Already paused by the user: don't pause it again.
		if (!IsPaused())
		{
			Pause();

			// Report paused even if Pause() failed: the device is gone, and Resume() can retry.
			UpdateState(RecordState::pause);
		}

		// Set it even when the user paused first: the device is gone either way.
		m_pausedByRouteLoss = true;
	}

	HRESULT Recorder::MoveToDefaultDevice(bool keepPaused)
	{
		std::string deviceId;
		HRESULT hr = m_engine->GetDefaultDeviceId(deviceId);
		if (FAILED(hr)) return hr;

		hr = MoveToDevice(deviceId, keepPaused);
		if (FAILED(hr)) return hr;

		// Dart must hear that the take left the device it asked for.
		if (!m_pConfig->deviceId.empty())
		{
			m_pConfig->deviceId.clear();
			if (m_callbacks.onConfigChanged) m_callbacks.onConfigChanged(*m_pConfig);
		}

		return hr;
	}

	HRESULT Recorder::MoveToDevice(const std::string& deviceId, bool keepPaused)
	{
		// Keep the sink: a new media type would make it drop samples without an error.
		HRESULT hr = m_engine->Open(*m_pConfig, deviceId);

		if (SUCCEEDED(hr) && keepPaused)
		{
			// Media Foundation only pauses a started source, so start it first.
			hr = m_engine->Start();
			if (SUCCEEDED(hr)) hr = m_engine->Pause();
		}
		else if (SUCCEEDED(hr))
		{
			// Shifts the timestamps to avoid a hole in the recording.
			m_clock.Resume();

			hr = m_engine->RequestSample();
		}

		if (FAILED(hr))
		{
			// Left open, it would pass for a device Resume() can restart.
			m_engine->Close();
			return hr;
		}

		m_pRouteWatch->Watch(Utf16FromUtf8(deviceId));
		return hr;
	}

	HRESULT Recorder::ResolveDevice(const std::string& deviceId, std::string& resolved) const
	{
		if (!deviceId.empty())
		{
			resolved = deviceId;
			return S_OK;
		}

		return m_engine->GetDefaultDeviceId(resolved);
	}

	HRESULT Recorder::Pause()
	{
		AssertOnDispatcher();

		if (!m_engine->IsOpen()) return S_OK;

		HRESULT hr = m_engine->Pause();

		if (SUCCEEDED(hr))
		{
			UpdateState(RecordState::pause);
		}

		return hr;
	}

	HRESULT Recorder::Resume()
	{
		AssertOnDispatcher();

		if (!m_pConfig) return S_OK;

		// A user pause resumes on its own device, or not at all.
		if (!m_pausedByRouteLoss)
		{
			HRESULT hr = m_engine->Start();
			if (FAILED(hr)) return hr;

			m_clock.Resume();
			// A device opened during the pause has no read in flight yet.
			return m_engine->RequestSample();
		}

		// The lost device's source starts but fails its first read, so reopen the selected device or else the default one.
		HRESULT hr = m_pConfig->deviceId.empty() ? E_FAIL : MoveToDevice(m_pConfig->deviceId, false);
		if (FAILED(hr)) hr = MoveToDefaultDevice(false);

		// Stay paused with a distinct code, so the app can tell a missing device apart and retry later.
		if (FAILED(hr)) return E_RECORD_NO_INPUT_DEVICE;

		m_pausedByRouteLoss = false;
		return hr;
	}

	StopResult Recorder::Stop()
	{
		AssertOnDispatcher();

		if (m_dataWritten == 0)
		{
			return { Cancel(), std::wstring() };
		}

		auto path = m_pSink ? m_pSink->Path() : std::wstring();
		HRESULT hr = EndRecording();

		if (FAILED(hr)) return { hr, std::wstring() };

		UpdateState(RecordState::stop);
		return { hr, path };
	}

	HRESULT Recorder::Cancel()
	{
		AssertOnDispatcher();

		HRESULT hr = EndRecording(true);

		if (SUCCEEDED(hr))
		{
			UpdateState(RecordState::stop);
		}

		return hr;
	}

	bool Recorder::IsPaused()
	{
		AssertOnDispatcher();
		return m_recordState == RecordState::pause;
	}

	bool Recorder::IsRecording()
	{
		AssertOnDispatcher();
		return m_recordState == RecordState::record;
	}

	HRESULT Recorder::EndRecording(bool discard)
	{
		m_pRouteWatch->Stop();
		m_engine->Close();

		HRESULT hr = S_OK;

		if (m_pSink)
		{
			hr = m_pSink->Finalize();
			if (discard) m_pSink->Discard();
			m_pSink.reset();
		}

		m_clock.Restart();

		m_amplitude.reset();
		m_dataWritten = 0;

		m_pausedByRouteLoss = false;
		m_pConfig = nullptr;

		return hr;
	}

	HRESULT Recorder::Dispose()
	{
		AssertOnDispatcher();
		m_disposed = true;

		HRESULT hr = EndRecording();
		// DeviceNotificationClient::Start() registered on the dispatcher thread, so unregister on it too.
		m_pRouteWatch->Close();
		m_callbacks = {};

		return hr;
	}

	// Reporting the same state twice would show as a second take on the Dart side.
	void Recorder::UpdateState(RecordState state)
	{
		if (m_recordState == state) return;

		m_recordState = state;

		if (m_callbacks.onState) m_callbacks.onState(state);
	}

	std::map<std::string, double> Recorder::GetAmplitude()
	{
		AssertOnDispatcher();
		return {
			{"current", m_amplitude.current},
			{"max"    , m_amplitude.peak},
		};
	}
};
