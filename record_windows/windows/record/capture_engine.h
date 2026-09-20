#pragma once

#include <windows.h>
#include <mfidl.h>
#include <mfapi.h>
#include <Mfreadwrite.h>
#include <wrl/client.h>

#include <functional>
#include <memory>
#include <string>

#include "record_config.h"
#include "record/reader_callback.h"
#include "recorder_dispatcher.h"

namespace record_windows
{
	// Media Foundation capture on one input device. Reopened to change device.
	// Runs on the dispatcher thread, so nothing here is locked.
	class CaptureEngine
	{
	public:
		using SampleHandler = std::function<void(HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample)>;

		CaptureEngine(std::shared_ptr<RecorderDispatcher> dispatcher, SampleHandler onSample);
		~CaptureEngine();

		CaptureEngine(const CaptureEngine&) = delete;
		CaptureEngine& operator=(const CaptureEngine&) = delete;

		// An empty deviceId takes the current default device. Closes first,
		// so the same engine can move from one device to another.
		HRESULT Open(const RecordConfig& config, const std::string& deviceId);
		void Close();
		bool IsOpen() const { return m_pSource != nullptr; }

		// The media type the reader delivers, for the sink to accept.
		HRESULT GetInputType(IMFMediaType** ppType) const;

		// Asks for one sample; the handler answers on the dispatcher thread.
		HRESULT RequestSample();
		// Starts, or restarts after a pause.
		HRESULT Start();
		HRESULT Pause();

	private:
		HRESULT CreateSource(LPCWSTR deviceId);
		HRESULT CreateReaderAsync(const RecordConfig& config);

		template <typename T> using ComPtr = Microsoft::WRL::ComPtr<T>;

		std::shared_ptr<RecorderDispatcher> m_dispatcher;
		SampleHandler m_onSample;

		ComPtr<IMFMediaSource>            m_pSource;
		ComPtr<IMFPresentationDescriptor> m_pPresentationDescriptor;
		ComPtr<IMFSourceReader>           m_pReader;
		ComPtr<ReaderCallback>            m_pReaderCallback;
	};
}
