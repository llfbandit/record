#include "record.h"

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
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, (m_pConfig->encoderName == "pcm8bit") ? 8 : 16);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_pConfig->samplingRate);
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
			else if (m_pConfig->encoderName == "opus") audioFormat = MFAudioFormat_Opus;
			else if (m_pConfig->encoderName == "vorbisOgg") audioFormat = MFAudioFormat_Vorbis;
			else if (m_pConfig->encoderName == "flac") hr = CreateFlacProfile(pMediaType);
			else if (m_pConfig->encoderName == "pcm8bit") hr = CreatePcmProfile(pMediaType);
			else if (m_pConfig->encoderName == "pcm16bit") hr = CreatePcmProfile(pMediaType);
			else hr = CreateACCProfile(pMediaType);
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
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_pConfig->samplingRate);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_pConfig->numChannels);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AVG_BITRATE, m_pConfig->bitRate);
			//hr = pMediaType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, bytesPerSecond);
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
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_pConfig->samplingRate);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_pConfig->numChannels);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AVG_BITRATE, m_pConfig->bitRate);
			//hr = pMediaType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, bytesPerSecond);
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
			// bitRates = { 4750, 5150, 5900, 6700, 7400, 7950, 10200, 12200 };

			// hr = pMediaType->SetUINT32(MF_MT_AVG_BITRATE, config.bitRate);
		}

		return hr;
	}

	HRESULT Recorder::CreatePcmProfile(IMFMediaType* pMediaType)
	{
		HRESULT hr = pMediaType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);

		auto bitsPerSample = (m_pConfig->encoderName == "pcm8bit") ? 8 : 16;

		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, bitsPerSample);
		}
		// Calculate derived values.
		UINT32 blockAlign = m_pConfig->numChannels * (bitsPerSample / 8);
		UINT32 bytesPerSecond = blockAlign * m_pConfig->samplingRate;

		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, m_pConfig->numChannels);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, m_pConfig->samplingRate);
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
			hr = pMediaType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, bitsPerSample);
		}
		if (SUCCEEDED(hr))
		{
			hr = pMediaType->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
		}

		return hr;
	}
};
