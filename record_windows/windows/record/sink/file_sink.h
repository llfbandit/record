#pragma once

#include "record/sink/record_sink.h"

#include <mfapi.h>
#include <Mfreadwrite.h>
#include <wrl/client.h>

namespace record_windows
{
	// Writes the take to a file through a Media Foundation sink writer.
	class FileSink : public IRecordSink
	{
	public:
		explicit FileSink(std::wstring path) : m_path(std::move(path)) {}

		HRESULT Open(const RecordConfig& config, IMFMediaType* pInputType) override;
		HRESULT Write(DWORD dwStreamIndex, IMFSample* pSample) override;
		HRESULT Finalize() override;
		void Discard() override;
		std::wstring Path() const override { return m_path; }

	private:
		std::wstring m_path;
		// WAV sizes are only known once the take is over.
		bool m_isWav = false;
		Microsoft::WRL::ComPtr<IMFSinkWriter> m_pWriter;
	};
}
