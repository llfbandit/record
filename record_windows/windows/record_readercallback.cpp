#include "record.h"
#include "record_windows_plugin.h"

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
				// Always process amplitude for all samples, even during warmup
				IMFMediaBuffer* pBuffer = NULL;
				HRESULT bufferHr = pSample->ConvertToContiguousBuffer(&pBuffer);
				if (SUCCEEDED(bufferHr))
				{
					BYTE* pChunk = NULL;
					DWORD size = 0;
					bufferHr = pBuffer->Lock(&pChunk, NULL, &size);
					if (SUCCEEDED(bufferHr))
					{
						// Calculate amplitude for ALL samples including warmup
						GetAmplitude(pChunk, size, 2);
						pBuffer->Unlock();
					}
					SafeRelease(pBuffer);
				}

				// Only process for recording if we're active
				if (m_bRecordingActive)
				{
					if (m_bFirstSample)
					{
						m_llBaseTime = llTimestamp;
						m_llRecordStartTime = llTimestamp;
						m_bFirstSample = false;
						m_dataWritten = 0;
					}

					// Process ALL samples immediately - no skipping
					// Save current timestamp in case of Pause
					m_llLastTime = llTimestamp;

					// rebase the time stamp
					LONGLONG adjustedTimestamp = llTimestamp - m_llBaseTime;
					
					// Ensure sample doesn't get zero timestamp
					if (adjustedTimestamp <= 0)
					{
						adjustedTimestamp = 1;
					}

					hr = pSample->SetSampleTime(adjustedTimestamp);

					// Write to file if there's a writer
					if (SUCCEEDED(hr) && m_pWriter)
					{
						hr = m_pWriter->WriteSample(dwStreamIndex, pSample);
					}

					if (SUCCEEDED(hr))
					{
						IMFMediaBuffer* pRecordBuffer = NULL;
						hr = pSample->ConvertToContiguousBuffer(&pRecordBuffer);

						if (SUCCEEDED(hr))
						{
							BYTE* pRecordChunk = NULL;
							DWORD recordSize = 0;
							hr = pRecordBuffer->Lock(&pRecordChunk, NULL, &recordSize);

							if (SUCCEEDED(hr))
							{
								// Update total data written
								m_dataWritten += recordSize;

								// Send data to stream when there's no writer
								if (m_recordEventHandler && !m_pWriter) {
									std::vector<uint8_t> bytes(pRecordChunk, pRecordChunk + recordSize);

									RecordWindowsPlugin::RunOnMainThread([this, bytes]() -> void {
										m_recordEventHandler->Success(std::make_unique<flutter::EncodableValue>(bytes));
									});
								}

								pRecordBuffer->Unlock();
							}

							SafeRelease(pRecordBuffer);
						}
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
