#pragma once

#include <windows.h>
#include <mfidl.h>

#include <string>

#include "record_config.h"

namespace record_windows
{
	// Where the captured samples go. One per take, and it outlives a device swap.
	class IRecordSink
	{
	public:
		virtual ~IRecordSink() = default;

		// pInputType is what the capture reader delivers.
		virtual HRESULT Open(const RecordConfig& config, IMFMediaType* pInputType) = 0;
		virtual HRESULT Write(DWORD dwStreamIndex, IMFSample* pSample) = 0;
		// Closes the take. Nothing is written after this.
		virtual HRESULT Finalize() = 0;

		// Throws away what was written. Nothing to do when there is no file.
		virtual void Discard() {}
		// The recorded file, empty when the take was streamed.
		virtual std::wstring Path() const { return {}; }
	};
}
