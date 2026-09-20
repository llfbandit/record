#include "record/capture_engine.h"

#include <assert.h>

#include "mediatype/record_mediatype.h"
#include "utils.h"

namespace record_windows
{
	CaptureEngine::CaptureEngine(std::shared_ptr<RecorderDispatcher> dispatcher, SampleHandler onSample)
		: m_dispatcher(std::move(dispatcher)),
		m_onSample(std::move(onSample))
	{
	}

	CaptureEngine::~CaptureEngine()
	{
		Close();
	}

	HRESULT CaptureEngine::Open(const RecordConfig& config, const std::string& deviceId)
	{
		Close();

		HRESULT hr;

		if (deviceId.empty())
		{
			hr = CreateSource(NULL);
		}
		else
		{
			auto endpointId = Utf16FromUtf8(deviceId);
			hr = CreateSource(endpointId.c_str());
		}

		if (SUCCEEDED(hr))
		{
			hr = CreateReaderAsync(config);
		}

		return hr;
	}

	void CaptureEngine::Close()
	{
		m_pReader.Reset();
		// MF may still deliver from this reader: drop rather than mix into a next take.
		if (m_pReaderCallback)
		{
			m_pReaderCallback->Disarm();
			m_pReaderCallback.Reset();
		}

		if (m_pSource)
		{
			m_pSource->Stop();
			m_pSource->Shutdown();
		}

		m_pSource.Reset();
		m_pPresentationDescriptor.Reset();
	}

	HRESULT CaptureEngine::GetInputType(IMFMediaType** ppType) const
	{
		if (!m_pReader) return E_NOT_VALID_STATE;

		return m_pReader->GetCurrentMediaType(0, ppType);
	}

	HRESULT CaptureEngine::RequestSample()
	{
		if (!m_pReader) return E_NOT_VALID_STATE;

		return m_pReader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM,
			0,
			NULL, NULL, NULL, NULL
		);
	}

	HRESULT CaptureEngine::Start()
	{
		if (!m_pSource) return E_NOT_VALID_STATE;

		PROPVARIANT var;
		PropVariantInit(&var);
		var.vt = VT_EMPTY;

		return m_pSource->Start(m_pPresentationDescriptor.Get(), NULL, &var);
	}

	HRESULT CaptureEngine::Pause()
	{
		if (!m_pSource) return E_NOT_VALID_STATE;

		return m_pSource->Pause();
	}

	HRESULT CaptureEngine::CreateSource(LPCWSTR deviceId)
	{
		ComPtr<IMFAttributes> pAttributes;

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
			hr = MFCreateDeviceSource(pAttributes.Get(), &m_pSource);
		}
		// Create presentation descriptor to handle Resume action
		if (SUCCEEDED(hr))
		{
			hr = m_pSource->CreatePresentationDescriptor(&m_pPresentationDescriptor);
		}

		return hr;
	}

	HRESULT CaptureEngine::CreateReaderAsync(const RecordConfig& config)
	{
		ComPtr<IMFAttributes> pAttributes;
		ComPtr<IMFMediaType> pMediaTypeIn;

		// One callback per reader, so a late sample from a previous reader can be told apart.
		assert(!m_pReaderCallback);
		// Attach: the callback is born with one reference.
		m_pReaderCallback.Attach(new ReaderCallback(m_dispatcher,
			[this](HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample) {
				if (m_onSample) m_onSample(hrStatus, dwStreamIndex, llTimestamp, pSample);
			}));

		HRESULT hr = MFCreateAttributes(&pAttributes, 1);
		if (SUCCEEDED(hr))
		{
			hr = pAttributes->SetUnknown(MF_SOURCE_READER_ASYNC_CALLBACK, m_pReaderCallback.Get());
		}
		if (SUCCEEDED(hr))
		{
			hr = MFCreateSourceReaderFromMediaSource(m_pSource.Get(), pAttributes.Get(), &m_pReader);
		}
		if (SUCCEEDED(hr))
		{
			hr = MediaType::CreateInputProfile(config, &pMediaTypeIn);
		}
		if (SUCCEEDED(hr))
		{
			hr = m_pReader->SetCurrentMediaType(0, NULL, pMediaTypeIn.Get());
		}

		return hr;
	}
}
