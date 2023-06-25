#include "record.h"

#pragma warning(disable: 4201)
#include <aviriff.h>

namespace record_windows
{
	HRESULT Recorder::CreateAudioProfileIn(IMFMediaType** ppMediaType)
	{
		HRESULT hr = S_OK;

		IMFMediaType* pMediaType = NULL;

		hr = MFCreateMediaType(&pMediaType);

		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_pConfig->sampleRate);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_pConfig->numChannels);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AVG_BITRATE, m_pConfig->bitRate);
		}
		if (SUCCEEDED(hr))
		{
			*ppMediaType = pMediaType;
			(*ppMediaType)->AddRef();
		}

		SafeRelease(&pMediaType);

		return hr;
	}

	HRESULT Recorder::CreateAudioProfileOut(IMFMediaType** ppMediaType)
	{
		HRESULT hr = S_OK;

		IMFMediaType* pMediaType = NULL;
		GUID audioFormat{};

		hr = MFCreateMediaType(&pMediaType);

		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
		}
		if (SUCCEEDED(hr))
		{
			if (m_pConfig->encoderName == "aacLc") hr = CreateACCProfile(pMediaType);
			else if (m_pConfig->encoderName == "aacEld") hr = CreateACCProfile(pMediaType);
			else if (m_pConfig->encoderName == "aacHe") hr = CreateACCProfile(pMediaType);
			else if (m_pConfig->encoderName == "amrNb") hr = CreateAmrNbProfile(pMediaType);
			else if (m_pConfig->encoderName == "amrWb") hr = CreateAmrNbProfile(pMediaType);
			else if (m_pConfig->encoderName == "flac") hr = CreateFlacProfile(pMediaType);
			else if (m_pConfig->encoderName == "pcm16bits") hr = CreatePcmProfile(pMediaType);
			else if (m_pConfig->encoderName == "wav") hr = CreatePcmProfile(pMediaType);
			else hr = E_NOTIMPL;
		}

		if (SUCCEEDED(hr))
		{
			*ppMediaType = pMediaType;
			(*ppMediaType)->AddRef();
		}

		SafeRelease(&pMediaType);

		return hr;
	}

	HRESULT Recorder::CreateACCProfile(IMFMediaType* pMediaType)
	{
		HRESULT hr = pMediaType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
		//if (SUCCEEDED(hr) && audioFormat == MFAudioFormat_AAC)
		//{
		//	if (config.encoderName == "aacHe")
		//	{
		//		hr = pMediaType->SetUINT32(MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION, 0x33); // High Efficiency v2 AAC Profile L2
		//	}
		//	else
		//	{
		//		hr = pMediaType->SetUINT32(MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION, 0x29); // AAC Profile L2
		//	}
		//}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_pConfig->sampleRate);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_pConfig->numChannels);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AVG_BITRATE, m_pConfig->bitRate);
		}

		return hr;
	}

	HRESULT Recorder::CreateFlacProfile(IMFMediaType* pMediaType)
	{
		HRESULT hr = pMediaType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_FLAC);

		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_pConfig->sampleRate);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_pConfig->numChannels);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AVG_BITRATE, m_pConfig->bitRate);
		}

		return hr;
	}

	HRESULT Recorder::CreateAmrNbProfile(IMFMediaType* pMediaType)
	{
		HRESULT hr = pMediaType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AMR_NB);

		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
		}
		if (SUCCEEDED(hr))
		{
			// Let the framework do it as VBR
			// bitRates = { 4750, 5150, 5900, 6700, 7400, 7950, 10200, 12200 };

			// hr = pMediaType->SetUINT32(MF_MT_AVG_BITRATE, config.bitRate);
		}

		return hr;
	}

	HRESULT Recorder::CreatePcmProfile(IMFMediaType* pMediaType)
	{
		HRESULT hr = pMediaType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);

		auto bitsPerSample = 16;

		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, bitsPerSample);
		}
		// Calculate derived values.
		UINT32 blockAlign = m_pConfig->numChannels * (bitsPerSample / 8);
		UINT32 bytesPerSecond = blockAlign * m_pConfig->sampleRate;

		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_pConfig->numChannels);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_pConfig->sampleRate);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, blockAlign);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, bytesPerSecond);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
		}

		return hr;
	}

	// WAV_FILE_HEADER
	// This structure contains the first part of the .wav file, up to the
	// data portion.
	struct WAV_FILE_HEADER
	{
		RIFFCHUNK       FileHeader;
		DWORD           fccWaveType;    // must be 'WAVE'
		RIFFCHUNK       WaveHeader;
		WAVEFORMATEX    WaveFormat;
		RIFFCHUNK       DataHeader;
	};

	HRESULT Recorder::FillWavHeader() {
		// Fill in the RIFF headers...
		WAVEFORMATEX* pWav = NULL;
		UINT cbSize = 0;
		DWORD cbWritten = 0;

		WAV_FILE_HEADER header;
		ZeroMemory(&header, sizeof(header));

		DWORD cbFileSize = m_dataWritten + sizeof(WAV_FILE_HEADER) - sizeof(RIFFCHUNK);

		HRESULT hr = MFCreateWaveFormatExFromMFMediaType(m_pMediaType, &pWav, &cbSize);

		if (SUCCEEDED(hr))
		{
			header.FileHeader.fcc = MAKEFOURCC('R', 'I', 'F', 'F');
			header.FileHeader.cb = cbFileSize;
			header.fccWaveType = MAKEFOURCC('W', 'A', 'V', 'E');
			header.WaveHeader.fcc = MAKEFOURCC('f', 'm', 't', ' ');
			header.WaveHeader.cb = RIFFROUND(sizeof(WAVEFORMATEX));

			CopyMemory(&header.WaveFormat, pWav, sizeof(WAVEFORMATEX));
			header.DataHeader.fcc = MAKEFOURCC('d', 'a', 't', 'a');
			header.DataHeader.cb = m_dataWritten;
		}

		// Move the file pointer back to the start of the file and write the
		// RIFF headers.
		if (SUCCEEDED(hr))
		{
			std::wstring wsPath = std::wstring(m_recordingPath.begin(), m_recordingPath.end());

			HANDLE hFile = CreateFile(wsPath.c_str(),
				GENERIC_READ | GENERIC_WRITE,
				0,                      
				NULL,                   
				OPEN_EXISTING,
				FILE_ATTRIBUTE_NORMAL,  
				NULL);                  

			if (hFile == INVALID_HANDLE_VALUE)
			{
				printf("Record: Error when opening WAVE file.");
				return E_FAIL;
			}

			if (SetFilePointer(hFile, 0, NULL, FILE_BEGIN) == INVALID_SET_FILE_POINTER)
			{
				printf("Record: Error when seeking to start of WAVE file.");
				CloseHandle(hFile);
				return E_FAIL;
			}

			if (!WriteFile(hFile, (BYTE*)&header, sizeof(WAV_FILE_HEADER), &cbWritten, NULL))
			{
				printf("Record: Error when writing WAVE file RIFF header.");
				CloseHandle(hFile);
				return E_FAIL;
			}

			if (!CloseHandle(hFile))
			{
				printf("Record: Error when closing WAVE file.");
				return E_FAIL;
			}
		}

		return hr;
	}
};
