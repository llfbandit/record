/*
*
* https://learn.microsoft.com/en-us/windows/uwp/audio-video-camera/codec-query
* https://learn.microsoft.com/en-us/uwp/api/windows.media.core.codecsubtypes?view=winrt-22621
*
* https://github.com/microsoft/Windows-universal-samples/blob/main/Samples/CameraStarterKit/cpp/MainPage.xaml.h
* https://github.com/microsoft/Windows-universal-samples/blob/main/Samples/CameraStarterKit/cpp/MainPage.xaml.cpp
*
* https://learn.microsoft.com/en-us/windows/win32/medfound/audio-video-capture
* WMF FLAC https://stackoverflow.com/questions/48930499/how-do-i-encode-raw-48khz-32bits-pcm-to-flac-using-microsoft-media-foundation
* WMF AAC https://learn.microsoft.com/en-us/windows/win32/medfound/aac-encoder
* WMF https://learn.microsoft.com/en-us/windows/win32/medfound/audio-video-capture-in-media-foundation
* https://learn.microsoft.com/en-us/windows/win32/medfound/tutorial--using-the-sink-writer-to-encode-video
* https://learn.microsoft.com/en-us/windows/win32/medfound/audio-subtype-guids
* https://github.com/microsoft/Windows-classic-samples/tree/main/Samples/Win7Samples/multimedia/mediafoundation/wavsink
* https://learn.microsoft.com/fr-fr/windows/win32/api/_mf/
* https://stackoverflow.com/questions/12917256/windows-media-foundation-recording-audio
* https://github.com/sipsorcery/mediafoundationsamples/blob/master/MFAudioCaptureToSAR/MFAudioCaptureToSAR.cpp
* https://chromium-review.googlesource.com/c/chromium/src/+/3293969
*
* https://learn.microsoft.com/en-us/windows/win32/medfound/uncompressed-audio-media-types
*
* https://learn.microsoft.com/en-us/windows/win32/medfound/tutorial--encoding-an-mp4-file-
*/

#include "record.h"

namespace record_windows
{
	// static
	HRESULT Recorder::CreateInstance(EventStreamHandler<>* stateEventHandler, EventStreamHandler<>* recordEventHandler, Recorder** ppRecorder)
	{
		auto pRecorder = new (std::nothrow) Recorder(stateEventHandler, recordEventHandler);

		if (pRecorder == NULL)
		{
			return E_OUTOFMEMORY;
		}

		// The Recorder constructor sets the ref count to 1.
		*ppRecorder = pRecorder;

		return S_OK;
	}

	Recorder::Recorder(EventStreamHandler<>* stateEventHandler, EventStreamHandler<>* recordEventHandler)
		: m_nRefCount(1),
		m_critsec(),
		m_pConfig(nullptr),
		m_pSource(NULL),
		m_pReader(NULL),
		m_pWriter(NULL),
		m_pPresentationDescriptor(NULL),
		m_stateEventHandler(stateEventHandler),
		m_recordEventHandler(recordEventHandler),
		m_recordingPath(std::string())
	{
	}

	Recorder::~Recorder()
	{
		Dispose();
	}

	HRESULT Recorder::Start(std::unique_ptr<RecordConfig> config, std::string path)
	{
		HRESULT hr = InitRecording(std::move(config));

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
		HRESULT hr = InitRecording(std::move(config));

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

		m_pConfig = std::move(config);

		if (SUCCEEDED(hr))
		{
			if (!m_mfStarted)
			{
				hr = MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);
			}
			if (SUCCEEDED(hr))
			{
				m_mfStarted = true;
			}
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
		HRESULT hr = S_OK;

		if (m_pSource)
		{
			hr = m_pSource->Pause();

			if (SUCCEEDED(hr))
			{
				UpdateState(RecordState::pause);
			}
		}

		return S_OK;
	}

	HRESULT Recorder::Resume()
	{
		HRESULT hr = S_OK;

		if (m_pSource)
		{
			PROPVARIANT var;
			PropVariantInit(&var);
			var.vt = VT_EMPTY;

			m_llBaseTime = m_llLastTime;

			hr = m_pSource->Start(m_pPresentationDescriptor, NULL, &var);

			if (SUCCEEDED(hr))
			{
				UpdateState(RecordState::record);
			}
		}

		return hr;
	}

	HRESULT Recorder::Stop()
	{
		HRESULT hr = EndRecording();

		if (SUCCEEDED(hr))
		{
			UpdateState(RecordState::stop);
		}

		return hr;
	}

	bool Recorder::IsPaused()
	{
		switch (m_recordState)
		{
		case RecordState::pause:
			return true;
		default:
			return false;
		}
	}

	bool Recorder::IsRecording()
	{
		switch (m_recordState)
		{
		case RecordState::record:
			return true;
		default:
			return false;
		}
	}

	HRESULT Recorder::EndRecording()
	{
		HRESULT hr = S_OK;

		if (m_pSource)
		{
			hr = m_pSource->Stop();

			if (SUCCEEDED(hr))
			{
				hr = m_pSource->Shutdown();
			}
		}

		if (m_pWriter)
		{
			hr = m_pWriter->Finalize();
		}

		m_bFirstSample = true;
		m_llBaseTime = 0;
		m_llLastTime = 0;

		m_amplitude = -160;
		m_maxAmplitude = -160;

		if (m_mfStarted)
		{
			hr = MFShutdown();
			if (SUCCEEDED(hr))
			{
				m_mfStarted = false;
			}
		}

		SafeRelease(m_pSource);
		SafeRelease(m_pPresentationDescriptor);
		SafeRelease(m_pReader);
		SafeRelease(m_pWriter);
		m_pConfig = nullptr;
		m_recordingPath = std::string();

		return hr;
	}

	HRESULT Recorder::Dispose()
	{
		HRESULT hr = EndRecording();

		m_stateEventHandler = nullptr;
		m_recordEventHandler = nullptr;

		return hr;
	}

	void Recorder::UpdateState(RecordState state)
	{
		m_recordState = state;

		if (m_stateEventHandler) {
			m_stateEventHandler->Success(std::make_unique<flutter::EncodableValue>(state));
		}
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

		hr = MFCreateAttributes(&pAttributes, 1);
		if (SUCCEEDED(hr))
		{
			hr = pAttributes->SetUnknown(MF_SOURCE_READER_ASYNC_CALLBACK, this);
		}
		if (SUCCEEDED(hr))
		{
			hr = MFCreateSourceReaderFromMediaSource(m_pSource, pAttributes, &m_pReader);
		}
		if (SUCCEEDED(hr))
		{
			hr = CreateAudioProfileIn(&pMediaTypeIn);
		}
		if (SUCCEEDED(hr))
		{
			hr = m_pReader->SetCurrentMediaType(0, NULL, pMediaTypeIn);
		}

		SafeRelease(&pMediaTypeIn);
		SafeRelease(&pAttributes);
		return hr;
	}

	HRESULT Recorder::CreateSinkWriter(std::string path)
	{
		IMFSinkWriter* pSinkWriter = NULL;
		IMFMediaType* pMediaTypeOut = NULL;
		IMFMediaType* pMediaTypeIn = NULL;
		DWORD          streamIndex = 0;

		std::wstring wsPath = std::wstring(path.begin(), path.end());
		HRESULT hr = MFCreateSinkWriterFromURL(wsPath.c_str(), NULL, NULL, &pSinkWriter);

		// Set the output media type.
		hr = CreateAudioProfileOut(&pMediaTypeOut);
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
		}

		SafeRelease(&pSinkWriter);
		SafeRelease(&pMediaTypeOut);
		SafeRelease(&pMediaTypeIn);

		return hr;
	}

	std::map<std::string, double> Recorder::GetAmplitude()
	{
		return {
			{"current", m_amplitude},
			{"max" , m_maxAmplitude},
		};
	}

	void Recorder::GetAmplitude(BYTE* chunk, int size, int bytesPerSample) {
		int maxSample = -160;

		if (bytesPerSample == 2) { // PCM 16 bits
			for (int i = 0; i < size; i += 2) {
				short big;
				big = chunk[i] << 8 | chunk[i + 1];

				int curSample = std::abs(big);
				if (curSample > maxSample) {
					maxSample = curSample;
				}
			}

			m_amplitude = 20 * std::log10(maxSample / 32767.0); // 16 signed bits 2^15
		}
		else /* if (bytesPerSample == 1) */ { // PCM 8 bits
			for (int i = 0; i < size; i++) {
				byte curSample = chunk[i];
				if (curSample > maxSample) {
					maxSample = curSample;
				}
			}

			m_amplitude = 20 * std::log10(maxSample / 255.0); // 8 unsigned bits 2^8
		}

		if (m_amplitude > m_maxAmplitude) {
			m_maxAmplitude = m_amplitude;
		}
	}

	std::string Recorder::GetRecordingPath()
	{
		return m_recordingPath;
	}
};
