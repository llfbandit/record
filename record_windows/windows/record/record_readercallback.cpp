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

		// With no read queued, no callback comes back: the take would stall without an error.
		if (SUCCEEDED(hr))
		{
			hr = m_engine->RequestSample();
		}

		if (FAILED(hr))
		{
			// Asking for another sample would only stall: end the take instead.
			auto errorText = std::system_category().message(hr);
			printf("Record: Error on sample (0x%X)\n%s\n", hr, errorText.c_str());

			// The reader may see the lost device before the notification does.
			if (IsDeviceLost(hr))
			{
				OnRouteLost();
			}
			else
			{
				// The system text may not be UTF-8, so Dart gets the code.
				char error[64];
				snprintf(error, sizeof(error), "Capture failed (0x%08X).", static_cast<unsigned>(hr));
				End(StopReason::error, false, error);
			}
		}
	}

	HRESULT Recorder::ProcessSample(DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample)
	{
		// A sample without a duration only makes the next resume overlap it.
		LONGLONG llDuration = 0;
		if (FAILED(pSample->GetSampleDuration(&llDuration))) llDuration = 0;

		if (m_clock.Rebase(llTimestamp, llDuration))
		{
			// A follow move rebases while already recording; UpdateState() skips the repeated state.
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
