#include "record/sink/file_sink.h"

#include "mediatype/record_mediatype.h"

namespace record_windows
{
	HRESULT FileSink::Open(const RecordConfig& config, IMFMediaType* pInputType)
	{
		m_isWav = config.encoderName == AudioEncoder::wav;

		Microsoft::WRL::ComPtr<IMFSinkWriter> pSinkWriter;
		Microsoft::WRL::ComPtr<IMFMediaType> pMediaTypeOut;
		DWORD streamIndex = 0;

		HRESULT hr = MFCreateSinkWriterFromURL(m_path.c_str(), NULL, NULL, &pSinkWriter);

		// Set the output media type.
		if (SUCCEEDED(hr))
		{
			hr = MediaType::CreateOutputProfile(config, &pMediaTypeOut);
		}
		if (SUCCEEDED(hr))
		{
			hr = pSinkWriter->AddStream(pMediaTypeOut.Get(), &streamIndex);
		}

		// Set the input media type.
		if (SUCCEEDED(hr))
		{
			hr = pSinkWriter->SetInputMediaType(streamIndex, pInputType, NULL);
		}

		// Tell the sink writer to Start accepting data.
		if (SUCCEEDED(hr))
		{
			hr = pSinkWriter->BeginWriting();
		}

		if (SUCCEEDED(hr))
		{
			m_pWriter = pSinkWriter;
		}
		else if (pSinkWriter)
		{
			// The writer already created the file: don't leave an empty one.
			pSinkWriter.Reset();
			DeleteFile(m_path.c_str());
		}

		return hr;
	}

	HRESULT FileSink::Write(DWORD dwStreamIndex, IMFSample* pSample)
	{
		if (!m_pWriter) return S_OK;

		return m_pWriter->WriteSample(dwStreamIndex, pSample);
	}

	HRESULT FileSink::Finalize()
	{
		HRESULT hr = S_OK;

		if (m_pWriter)
		{
			hr = m_pWriter->Finalize();
			m_pWriter.Reset();
		}

		if (m_isWav)
		{
			MediaType::FillWavHeader(m_path);
		}

		return hr;
	}

	void FileSink::Discard()
	{
		if (!m_path.empty())
		{
			DeleteFile(m_path.c_str());
		}
	}
}
