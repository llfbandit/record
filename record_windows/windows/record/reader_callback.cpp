#include "record/reader_callback.h"

#include <shlwapi.h>

namespace record_windows
{
	ReaderCallback::ReaderCallback(std::shared_ptr<RecorderDispatcher> dispatcher, Handler handler)
		: m_nRefCount(1),
		m_dispatcher(std::move(dispatcher)),
		m_handler(std::move(handler))
	{
	}

	void ReaderCallback::Disarm()
	{
		m_handler = nullptr;
	}

	STDMETHODIMP ReaderCallback::OnReadSample(HRESULT hrStatus, DWORD dwStreamIndex, DWORD, LONGLONG llTimestamp, IMFSample* pSample)
	{
		// Both refs are dropped by whichever side ends up owning the task.
		AddRef();
		if (pSample) pSample->AddRef();

		bool posted = m_dispatcher->Post([this, hrStatus, dwStreamIndex, llTimestamp, pSample] {
			// Copied: the handler may Disarm() this object while running.
			auto handler = m_handler;
			if (handler) handler(hrStatus, dwStreamIndex, llTimestamp, pSample);

			if (pSample) pSample->Release();
			Release();
		});

		if (!posted)
		{
			if (pSample) pSample->Release();
			Release();
		}

		return S_OK;
	}

	STDMETHODIMP ReaderCallback::QueryInterface(REFIID iid, void** ppv)
	{
		static const QITAB qit[] =
		{
			QITABENT(ReaderCallback, IMFSourceReaderCallback),
			{ 0 },
		};
		return QISearch(this, qit, iid, ppv);
	}

	STDMETHODIMP_(ULONG) ReaderCallback::AddRef()
	{
		return InterlockedIncrement(&m_nRefCount);
	}

	STDMETHODIMP_(ULONG) ReaderCallback::Release()
	{
		ULONG uCount = InterlockedDecrement(&m_nRefCount);
		if (uCount == 0)
		{
			delete this;
		}
		return uCount;
	}
}
