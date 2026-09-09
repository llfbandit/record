#include "record/record.h"

#include <cstdio>

namespace record_windows
{
	// Dispatcher thread, via ReaderCallback.
	void Recorder::OnSample(HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample)
	{
		AssertOnDispatcher();

		if (FAILED(hrStatus))
		{
			auto errorText = std::system_category().message(hrStatus);
			printf("Record: Error when reading sample (0x%X)\n%s\n", hrStatus, errorText.c_str());
			Stop();
			return;
		}

		HRESULT hr = S_OK;

		if (pSample)
		{
			hr = ProcessSample(dwStreamIndex, llTimestamp, pSample);
		}

		if (SUCCEEDED(hr) && m_pReader)
		{
			m_pReader->ReadSample(
				(DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, NULL, NULL, NULL, NULL);
		}
	}

	void Recorder::RebaseTimestamp(LONGLONG& llTimestamp)
	{
		if (m_bFirstSample)
		{
			m_llBaseTime = llTimestamp;
			m_bFirstSample = false;
			m_dataWritten = 0;
			if (m_bResuming)
			{
				// Paused before any sample arrived: treat as a fresh start.
				m_bResuming = false;
				UpdateState(RecordState::record);
			}
		}
		else if (m_bResuming)
		{
			m_bResuming = false;
			// Shift base so timestamps resume from the pause instead of jumping back.
			m_llBaseTime = llTimestamp - (m_llLastTime - m_llBaseTime);
			UpdateState(RecordState::record);
		}
		m_llLastTime = llTimestamp;
		llTimestamp -= m_llBaseTime;
	}

	HRESULT Recorder::ProcessSample(DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample)
	{
		RebaseTimestamp(llTimestamp);

		HRESULT hr = pSample->SetSampleTime(llTimestamp);
		if (FAILED(hr)) return hr;

		if (m_pWriter)
		{
			hr = m_pWriter->WriteSample(dwStreamIndex, pSample);
			if (FAILED(hr)) return hr;
		}

		return ProcessBuffer(pSample);
	}

	HRESULT Recorder::ProcessBuffer(IMFSample* pSample)
	{
		if (!m_pWriter && m_pStreamEncoder && m_callbacks.onChunk)
		{
			for (auto& packet : m_pStreamEncoder->Feed(pSample))
			{
				m_callbacks.onChunk(std::move(packet));
			}
		}

		IMFMediaBuffer* pBuffer = NULL;
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

		SafeRelease(pBuffer);
		return hr;
	}
};
