#include "record/record.h"
#include "audio_device/record_audio_device.h"
#include "record/sink/file_sink.h"
#include "record/sink/stream_sink.h"

namespace record_windows
{
	Recorder::Recorder(std::shared_ptr<RecorderDispatcher> dispatcher, RecorderCallbacks callbacks)
		: m_dispatcher(dispatcher),
		m_callbacks(std::move(callbacks)),
		m_engine(std::move(dispatcher),
			[this](HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample) {
				OnSample(hrStatus, dwStreamIndex, llTimestamp, pSample);
			})
	{
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
			hr = m_engine.GetInputType(&pInputType);

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
			hr = m_engine.RequestSample();
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

		if (SUCCEEDED(hr))
		{
			const int origSampleRate  = config->sampleRate;
			const int origNumChannels = config->numChannels;
			const int origBitRate     = config->bitRate;
			AudioDevice::AdjustConfigToDeviceCaps(*config);
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
			hr = m_engine.Open(*m_pConfig, m_pConfig->deviceId);
		}

		return hr;
	}

	HRESULT Recorder::Pause()
	{
		AssertOnDispatcher();

		if (!m_engine.IsOpen()) return S_OK;

		HRESULT hr = m_engine.Pause();

		if (SUCCEEDED(hr))
		{
			UpdateState(RecordState::pause);
		}

		return hr;
	}

	HRESULT Recorder::Resume()
	{
		AssertOnDispatcher();

		if (!m_engine.IsOpen()) return S_OK;

		HRESULT hr = m_engine.Start();

		if (SUCCEEDED(hr))
		{
			m_clock.Resume();
		}

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
		m_engine.Close();

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

		m_pConfig = nullptr;

		return hr;
	}

	HRESULT Recorder::Dispose()
	{
		AssertOnDispatcher();
		m_disposed = true;

		HRESULT hr = EndRecording();
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
