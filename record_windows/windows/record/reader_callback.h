#pragma once

#include <windows.h>
#include <mfidl.h>
#include <mfreadwrite.h>

#include <functional>
#include <memory>

#include "recorder_dispatcher.h"

namespace record_windows
{
	// The only object Media Foundation holds a reference to. Its whole job is to
	// get off MF's thread: samples are posted to the dispatcher.
	class ReaderCallback : public IMFSourceReaderCallback
	{
	public:
		using Handler = std::function<void(HRESULT hrStatus, DWORD dwStreamIndex, LONGLONG llTimestamp, IMFSample* pSample)>;

		ReaderCallback(std::shared_ptr<RecorderDispatcher> dispatcher, Handler handler);

		// Dispatcher thread. Samples still in flight from MF are dropped after this.
		void Disarm();

		// IUnknown methods
		STDMETHODIMP QueryInterface(REFIID iid, void** ppv);
		STDMETHODIMP_(ULONG) AddRef();
		STDMETHODIMP_(ULONG) Release();

		// IMFSourceReaderCallback methods
		STDMETHODIMP OnReadSample(HRESULT hrStatus, DWORD dwStreamIndex, DWORD dwStreamFlags, LONGLONG llTimestamp, IMFSample* pSample);
		STDMETHODIMP OnEvent(DWORD, IMFMediaEvent*) { return S_OK; }
		STDMETHODIMP OnFlush(DWORD) { return S_OK; }

	private:
		virtual ~ReaderCallback() = default;

		long m_nRefCount;
		// Shared: MF may hold this object after the recorder and its wrapper are gone.
		std::shared_ptr<RecorderDispatcher> m_dispatcher;
		// Dispatcher thread only.
		Handler m_handler;
	};
}
