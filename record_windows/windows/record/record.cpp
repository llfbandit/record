#include "record/record.h"
#include "audio_device/record_audio_device.h"
#include "mediatype/record_mediatype.h"
#include "encoder/aac_adts_encoder.h"
#include "encoder/pcm_encoder.h"

namespace record_windows
{
	Recorder::Recorder(std::shared_ptr<RecorderDispatcher> dispatcher, RecorderCallbacks callbacks)
		: m_dispatcher(std::move(dispatcher)),
		m_callbacks(std::move(callbacks)),
		m_pSource(NULL),
		m_pPresentationDescriptor(NULL),
		m_pReader(NULL),
		m_pReaderCallback(NULL),
		m_pWriter(NULL),
		m_pMediaType(NULL),
		m_recordingPath(std::wstring()),
		m_pConfig(nullptr)
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

		hr = InitRecording(std::move(config));

		if (SUCCEEDED(hr))
		{
			m_recordingPath = path;
			hr = CreateSinkWriter(path);
		}
		if (SUCCEEDED(hr))
		{
			// Request the first sample
			hr = m_pReader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM,
				0,
				NULL, NULL, NULL, NULL
			);
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

	HRESULT Recorder::StartStream(std::unique_ptr<RecordConfig> config)
	{
		AssertOnDispatcher();
		if (m_disposed) return E_ABORT;

		const auto& enc = config->encoderName;
		const bool isAac = enc == AudioEncoder::aacLc;
		const bool isPcm = enc == AudioEncoder::pcm16bits;

		if (!isAac && !isPcm)
		{
			return E_NOTIMPL;
		}

		HRESULT hr = InitRecording(std::move(config));

		if (SUCCEEDED(hr))
		{
			if (isAac)
			{
				AacAdtsEncoder* pEncoder = nullptr;
				hr = AacAdtsEncoder::Create(*m_pConfig, &pEncoder);
				if (SUCCEEDED(hr)) m_pStreamEncoder.reset(pEncoder);
			}
			else
			{
				m_pStreamEncoder = std::make_unique<PcmEncoder>();
			}
		}
		if (SUCCEEDED(hr))
		{
			// Request the first sample
			hr = m_pReader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM,
				0,
				NULL, NULL, NULL, NULL
			);
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

	HRESULT Recorder::InitRecording(std::unique_ptr<RecordConfig> config)
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
			if (m_pConfig->deviceId.length() != 0)
			{
				auto deviceId = std::wstring(m_pConfig->deviceId.begin(), m_pConfig->deviceId.end());
				hr = CreateAudioCaptureDevice(deviceId.c_str());
			}
			else
			{
				hr = CreateAudioCaptureDevice(NULL);
			}
		}
		if (SUCCEEDED(hr))
		{
			hr = CreateSourceReaderAsync();
		}

		return hr;
	}

	HRESULT Recorder::Pause()
	{
		AssertOnDispatcher();
		HRESULT hr = S_OK;

		if (m_pSource)
		{
			hr = m_pSource->Pause();

			if (SUCCEEDED(hr))
			{
				UpdateState(RecordState::pause);
			}
		}

		return hr;
	}

	HRESULT Recorder::Resume()
	{
		AssertOnDispatcher();
		HRESULT hr = S_OK;

		if (m_pSource)
		{
			PROPVARIANT var;
			PropVariantInit(&var);
			var.vt = VT_EMPTY;

			hr = m_pSource->Start(m_pPresentationDescriptor, NULL, &var);

			if (SUCCEEDED(hr))
			{
				m_bResuming = true;
			}
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

		auto path = m_recordingPath;
		HRESULT hr = EndRecording();

		if (FAILED(hr)) return { hr, std::wstring() };

		UpdateState(RecordState::stop);
		return { hr, path };
	}

	HRESULT Recorder::Cancel()
	{
		AssertOnDispatcher();
		auto recordingPath = m_recordingPath;
		HRESULT hr = EndRecording();

		if (SUCCEEDED(hr))
		{
			UpdateState(RecordState::stop);

			if (!recordingPath.empty())
			{
				DeleteFile(recordingPath.c_str());
			}
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

	HRESULT Recorder::EndRecording()
	{
		HRESULT hr = S_OK;

		SafeRelease(m_pReader);
		// MF may still deliver from this reader: drop rather than mix into a next take.
		if (m_pReaderCallback)
		{
			m_pReaderCallback->Disarm();
			SafeRelease(m_pReaderCallback);
		}

		if (m_pSource)
		{
			// The reader already shut the source down: only Finalize tells the outcome.
			m_pSource->Stop();
			m_pSource->Shutdown();
		}

		if (m_pWriter)
		{
			hr = m_pWriter->Finalize();
		}

		if (m_pConfig && m_pConfig->encoderName == AudioEncoder::wav) {
			MediaType::FillWavHeader(m_recordingPath);
		}

		m_bFirstSample = true;
		m_bResuming    = false;
		m_llBaseTime   = 0;
		m_llLastTime   = 0;

		m_amplitude.reset();
		m_dataWritten = 0;

		m_pStreamEncoder.reset();

		SafeRelease(m_pSource);
		SafeRelease(m_pPresentationDescriptor);
		SafeRelease(m_pWriter);
		SafeRelease(m_pMediaType);
		m_pConfig = nullptr;
		m_recordingPath = std::wstring();

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

	void Recorder::UpdateState(RecordState state)
	{
		m_recordState = state;

		if (m_callbacks.onState) m_callbacks.onState(state);
	}

	HRESULT Recorder::CreateAudioCaptureDevice(LPCWSTR deviceId)
	{
		IMFAttributes* pAttributes = NULL;

		HRESULT hr = MFCreateAttributes(&pAttributes, 2);

		// Set the device type to audio.
		if (SUCCEEDED(hr))
		{
			hr = pAttributes->SetGUID(
				MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
				MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_AUDCAP_GUID
			);
		}

		// Set the endpoint ID.
		if (SUCCEEDED(hr) && deviceId)
		{
			hr = pAttributes->SetString(
				MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_AUDCAP_ENDPOINT_ID,
				deviceId
			);
		}

		// Create the source
		if (SUCCEEDED(hr))
		{
			hr = MFCreateDeviceSource(pAttributes, &m_pSource);
		}
		// Create presentation descriptor to handle Resume action
		if (SUCCEEDED(hr))
		{
			hr = m_pSource->CreatePresentationDescriptor(&m_pPresentationDescriptor);
		}

		SafeRelease(&pAttributes);
		return hr;
	}

	HRESULT Recorder::CreateSourceReaderAsync()
	{
		HRESULT hr = S_OK;
		IMFAttributes* pAttributes = NULL;
		IMFMediaType* pMediaTypeIn = NULL;

		// One callback per reader, so a late sample from a previous reader can be told apart.
		assert(m_pReaderCallback == NULL);
		m_pReaderCallback = new ReaderCallback(m_dispatcher,
			[this](HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample) {
				OnSample(hrStatus, dwStreamIndex, llTimestamp, pSample);
			});

		hr = MFCreateAttributes(&pAttributes, 1);
		if (SUCCEEDED(hr))
		{
			hr = pAttributes->SetUnknown(MF_SOURCE_READER_ASYNC_CALLBACK, m_pReaderCallback);
		}
		if (SUCCEEDED(hr))
		{
			hr = MFCreateSourceReaderFromMediaSource(m_pSource, pAttributes, &m_pReader);
		}
		if (SUCCEEDED(hr))
		{
			hr = MediaType::CreateInputProfile(*m_pConfig, &pMediaTypeIn);
		}
		if (SUCCEEDED(hr))
		{
			hr = m_pReader->SetCurrentMediaType(0, NULL, pMediaTypeIn);
		}

		SafeRelease(&pMediaTypeIn);
		SafeRelease(&pAttributes);
		return hr;
	}

	HRESULT Recorder::CreateSinkWriter(std::wstring path)
	{
		IMFSinkWriter* pSinkWriter = NULL;
		IMFMediaType* pMediaTypeOut = NULL;
		IMFMediaType* pMediaTypeIn = NULL;
		DWORD          streamIndex = 0;

		HRESULT hr = MFCreateSinkWriterFromURL(path.c_str(), NULL, NULL, &pSinkWriter);

		// Set the output media type.
		if (SUCCEEDED(hr))
		{
			hr = MediaType::CreateOutputProfile(*m_pConfig, &pMediaTypeOut);
		}
		if (SUCCEEDED(hr))
		{
			hr = pSinkWriter->AddStream(pMediaTypeOut, &streamIndex);
		}

		// Set the input media type.
		if (SUCCEEDED(hr))
		{
			hr = m_pReader->GetCurrentMediaType(streamIndex, &pMediaTypeIn);
		}
		if (SUCCEEDED(hr))
		{
			hr = pSinkWriter->SetInputMediaType(streamIndex, pMediaTypeIn, NULL);
		}

		// Tell the sink writer to Start accepting data.
		if (SUCCEEDED(hr))
		{
			hr = pSinkWriter->BeginWriting();
		}

		if (SUCCEEDED(hr))
		{
			m_pWriter = pSinkWriter;
			m_pWriter->AddRef();
			m_pMediaType = pMediaTypeOut;
			m_pMediaType->AddRef();
		}

		SafeRelease(&pSinkWriter);
		SafeRelease(&pMediaTypeOut);
		SafeRelease(&pMediaTypeIn);

		return hr;
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
