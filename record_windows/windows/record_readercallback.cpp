#include "record.h"

namespace record_windows
{
	STDMETHODIMP Recorder::OnEvent(DWORD, IMFMediaEvent*)
	{
		return S_OK;
	}

	STDMETHODIMP Recorder::OnFlush(DWORD)
	{
		return S_OK;
	}

	HRESULT Recorder::OnReadSample(
		HRESULT hrStatus,
		DWORD dwStreamIndex,
		DWORD dwStreamFlags,
		LONGLONG llTimestamp,
		IMFSample* pSample      // Can be NULL
	)
	{
		AutoLock lock(m_critsec);

		HRESULT hr = S_OK;

		if (SUCCEEDED(hrStatus))
		{
			if (pSample)
			{
				if (m_bFirstSample)
				{
					m_llBaseTime = llTimestamp;
					m_bFirstSample = false;
					m_dataWritten = 0;
				}

				// Save current timestamp in case of Pause
				m_llLastTime = llTimestamp;

				// rebase the time stamp
				llTimestamp -= m_llBaseTime;

				hr = pSample->SetSampleTime(llTimestamp);

				// Write to file if there's a writer
				if (SUCCEEDED(hr) && m_pWriter)
				{
					hr = m_pWriter->WriteSample(dwStreamIndex, pSample);
				}

				if (SUCCEEDED(hr))
				{
					IMFMediaBuffer* pBuffer = NULL;
					hr = pSample->ConvertToContiguousBuffer(&pBuffer);

					if (SUCCEEDED(hr))
					{
						BYTE* pChunk = NULL;
						DWORD size = 0;
						hr = pBuffer->Lock(&pChunk, NULL, &size);

						if (SUCCEEDED(hr))
						{
							// Update total data written
							m_dataWritten += size;

							// Send data to stream when there's no writer
							if (m_recordEventHandler && !m_pWriter) {
								std::vector<uint8_t> bytes(pChunk, pChunk + size);
								m_recordEventHandler->Success(std::make_unique<flutter::EncodableValue>(bytes));
							}

							GetAmplitude(pChunk, size, 2);

							pBuffer->Unlock();
						}

						SafeRelease(pBuffer);
					}
				}
			}

			if (SUCCEEDED(hr))
			{
				// Read another sample
				hr = m_pReader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM,
					0,
					NULL, NULL, NULL, NULL
				);
			}

		}
		else
		{
			// Reader error.
			auto errorText = std::system_category().message(hrStatus);
			printf("Record: Error when reading sample (0x%X)\n%s\n", hrStatus, errorText.c_str());

			Stop();
		}

		return hr;
	}
};
