#pragma once

#include <functional>
#include <memory>
#include <vector>

#include "encoder/stream_encoder.h"
#include "record/sink/record_sink.h"

namespace record_windows
{
	// Hands the take to Dart as it comes, encoded but not containerized.
	class StreamSink : public IRecordSink
	{
	public:
		using ChunkHandler = std::function<void(std::vector<uint8_t>)>;

		// Answered before a take starts, so no device is set up for nothing.
		static bool Supports(const std::string& encoderName);

		explicit StreamSink(ChunkHandler onChunk) : m_onChunk(std::move(onChunk)) {}

		HRESULT Open(const RecordConfig& config, IMFMediaType* pInputType) override;
		HRESULT Write(DWORD dwStreamIndex, IMFSample* pSample) override;
		HRESULT Finalize() override;

	private:
		ChunkHandler m_onChunk;
		std::unique_ptr<IStreamEncoder> m_pEncoder;
	};
}
