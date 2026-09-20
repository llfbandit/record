#include "record/sink/stream_sink.h"

#include "encoder/aac_adts_encoder.h"
#include "encoder/pcm_encoder.h"

namespace record_windows
{
	bool StreamSink::Supports(const std::string& encoderName)
	{
		return encoderName == AudioEncoder::aacLc
			|| encoderName == AudioEncoder::pcm16bits;
	}

	HRESULT StreamSink::Open(const RecordConfig& config, IMFMediaType*)
	{
		if (config.encoderName == AudioEncoder::aacLc)
		{
			AacAdtsEncoder* pEncoder = nullptr;
			HRESULT hr = AacAdtsEncoder::Create(config, &pEncoder);
			if (FAILED(hr)) return hr;

			m_pEncoder.reset(pEncoder);
			return S_OK;
		}

		if (config.encoderName == AudioEncoder::pcm16bits)
		{
			m_pEncoder = std::make_unique<PcmEncoder>();
			return S_OK;
		}

		return E_NOTIMPL;
	}

	HRESULT StreamSink::Write(DWORD, IMFSample* pSample)
	{
		if (!m_pEncoder || !m_onChunk) return S_OK;

		for (auto& packet : m_pEncoder->Feed(pSample))
		{
			m_onChunk(std::move(packet));
		}

		return S_OK;
	}

	HRESULT StreamSink::Finalize()
	{
		m_pEncoder.reset();

		return S_OK;
	}
}
