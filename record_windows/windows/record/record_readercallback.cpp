#include "record/record.h"

#include <cstdio>

namespace record_windows
{
	// Dispatcher thread, via ReaderCallback.
	void Recorder::OnSample(HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample)
	{
		AssertOnDispatcher();

		HRESULT hr = hrStatus;

		if (SUCCEEDED(hr) && pSample)
		{
			hr = ProcessSample(dwStreamIndex, llTimestamp, pSample);
		}

		if (FAILED(hr))
		{
			// Asking for another sample would only stall: end the take instead.
			auto errorText = std::system_category().message(hr);
			printf("Record: Error on sample (0x%X)\n%s\n", hr, errorText.c_str());
			Stop();
			return;
		}

		m_engine.RequestSample();
	}

	HRESULT Recorder::ProcessSample(DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample)
	{
		if (m_clock.Rebase(llTimestamp))
		{
			UpdateState(RecordState::record);
		}

		HRESULT hr = pSample->SetSampleTime(llTimestamp);
		if (FAILED(hr)) return hr;

		if (m_pSink)
		{
			hr = m_pSink->Write(dwStreamIndex, pSample);
			if (FAILED(hr)) return hr;
		}

		return TrackLevel(pSample);
	}

	// Also counts the bytes, to tell an empty take from a real one.
	HRESULT Recorder::TrackLevel(IMFSample* pSample)
	{
		Microsoft::WRL::ComPtr<IMFMediaBuffer> pBuffer;
		HRESULT hr = pSample->ConvertToContiguousBuffer(&pBuffer);
		if (FAILED(hr)) return hr;

		BYTE* pChunk = NULL;
		DWORD size   = 0;
		hr = pBuffer->Lock(&pChunk, NULL, &size);

		if (SUCCEEDED(hr))
		{
			m_dataWritten += size;
			m_amplitude.update(pChunk, size);
			pBuffer->Unlock();
		}

		return hr;
	}
};
