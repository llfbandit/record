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
				if (m_bFirstSample)
				{
					m_llBaseTime = llTimestamp;
					m_llRecordStartTime = llTimestamp;
					m_bFirstSample = false;
					m_dataWritten = 0;
					m_sampleSkipCount = 0; // Reset skip counter
				}

				// Strategy: Buffer first few samples and adjust their timestamps
				if (m_sampleSkipCount < 10) // Buffer more samples for better coverage
				{
					m_sampleSkipCount++;
					
					// Clone and buffer the sample for later processing
					if (m_sampleBuffer.size() < 10) // Limit buffer size
					{
						IMFSample* pClonedSample = NULL;
						HRESULT cloneHr = MFCreateSample(&pClonedSample);
						if (SUCCEEDED(cloneHr))
						{
							IMFMediaBuffer* pSourceBuffer = NULL;
							cloneHr = pSample->ConvertToContiguousBuffer(&pSourceBuffer);
							if (SUCCEEDED(cloneHr))
							{
								DWORD sourceSize = 0;
								cloneHr = pSourceBuffer->GetCurrentLength(&sourceSize);
								if (SUCCEEDED(cloneHr))
								{
									IMFMediaBuffer* pClonedBuffer = NULL;
									cloneHr = MFCreateMemoryBuffer(sourceSize, &pClonedBuffer);
									if (SUCCEEDED(cloneHr))
									{
										BYTE* pSourceData = NULL, *pClonedData = NULL;
										cloneHr = pSourceBuffer->Lock(&pSourceData, NULL, NULL);
										if (SUCCEEDED(cloneHr))
										{
											cloneHr = pClonedBuffer->Lock(&pClonedData, NULL, NULL);
											if (SUCCEEDED(cloneHr))
											{
												memcpy(pClonedData, pSourceData, sourceSize);
												pClonedBuffer->SetCurrentLength(sourceSize);
												pClonedBuffer->Unlock();
											}
											pSourceBuffer->Unlock();
										}
										if (SUCCEEDED(cloneHr))
										{
											pClonedSample->AddBuffer(pClonedBuffer);
											pClonedSample->SetSampleTime(llTimestamp);
											m_sampleBuffer.push(pClonedSample);
										}
										SafeRelease(pClonedBuffer);
									}
								}
								SafeRelease(pSourceBuffer);
							}
						}
					}
					
					// Still process for amplitude but don't write
					IMFMediaBuffer* pBuffer = NULL;
					hr = pSample->ConvertToContiguousBuffer(&pBuffer);
					if (SUCCEEDED(hr))
					{
						BYTE* pChunk = NULL;
						DWORD size = 0;
						hr = pBuffer->Lock(&pChunk, NULL, &size);
						if (SUCCEEDED(hr))
						{
							GetAmplitude(pChunk, size, 2);
							pBuffer->Unlock();
						}
						SafeRelease(pBuffer);
					}
				}
				else
				{
					// Process buffered samples first (only once)
					if (!m_sampleBuffer.empty())
					{
						while (!m_sampleBuffer.empty())
						{
							IMFSample* pBufferedSample = m_sampleBuffer.front();
							m_sampleBuffer.pop();
							
							if (pBufferedSample && m_pWriter)
							{
								LONGLONG bufferedTimestamp;
								pBufferedSample->GetSampleTime(&bufferedTimestamp);
								bufferedTimestamp -= m_llBaseTime;
								if (bufferedTimestamp <= 0) bufferedTimestamp = 1;
								pBufferedSample->SetSampleTime(bufferedTimestamp);
								
								m_pWriter->WriteSample(dwStreamIndex, pBufferedSample);
							}
							SafeRelease(pBufferedSample);
						}
					}

					// Now process current sample normally
					// Save current timestamp in case of Pause
					m_llLastTime = llTimestamp;

					// rebase the time stamp
					llTimestamp -= m_llBaseTime;
					
					// Ensure sample doesn't get zero timestamp
					if (llTimestamp <= 0)
					{
						llTimestamp = 1;
					}

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

									RecordWindowsPlugin::RunOnMainThread([this, bytes]() -> void {
										m_recordEventHandler->Success(std::make_unique<flutter::EncodableValue>(bytes));
									});
								}

								GetAmplitude(pChunk, size, 2);

								pBuffer->Unlock();
							}

							SafeRelease(pBuffer);
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
