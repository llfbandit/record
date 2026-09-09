#include "platform_thread.h"

#include <cassert>
#include <cstdio>

namespace record_windows
{
	namespace
	{
		constexpr wchar_t kWindowClassName[] = L"record_windows.PlatformThread";
		constexpr UINT WM_RUN_DELEGATE = WM_USER + 101;
	}

	PlatformThread::PlatformThread()
	{
		// Once per process: a second engine would otherwise fail on an existing class.
		static const ATOM sClass = [] {
			WNDCLASS wc{};
			wc.lpfnWndProc = PlatformThread::WndProc;
			wc.hInstance = GetModuleHandle(nullptr);
			wc.lpszClassName = kWindowClassName;
			return RegisterClass(&wc);
		}();

		if (sClass != 0)
		{
			// Message-only: reaches the pump this thread already runs.
			m_hwnd = CreateWindowEx(0, kWindowClassName, L"", 0, 0, 0, 0, 0,
				HWND_MESSAGE, nullptr, GetModuleHandle(nullptr), this);
		}

		// Without it no recorder on this engine can ever answer: say so here.
		if (!m_hwnd)
		{
			printf("Record: failed to create the platform thread window (0x%lX)\n", GetLastError());
			assert(false);
		}
	}

	PlatformThread::~PlatformThread()
	{
		if (m_hwnd) DestroyWindow(m_hwnd);
	}

	void PlatformThread::Post(std::function<void()> callback)
	{
		// Nothing would ever drain it: drop instead of growing the queue for good.
		if (!m_hwnd) return;

		{
			std::lock_guard<std::mutex> lock(m_mutex);
			m_callbacks.push(std::move(callback));
			// Drain empties the whole queue: one wake-up in flight is enough.
			if (m_wakeupPending) return;
			m_wakeupPending = true;
		}

		if (PostMessage(m_hwnd, WM_RUN_DELEGATE, 0, 0)) return;

		// Queue full: the callback stays for the next Post to wake.
		std::lock_guard<std::mutex> lock(m_mutex);
		m_wakeupPending = false;
	}

	void PlatformThread::Drain()
	{
		{
			std::lock_guard<std::mutex> lock(m_mutex);
			m_wakeupPending = false;
		}

		for (;;)
		{
			std::function<void()> cb;
			{
				std::lock_guard<std::mutex> lock(m_mutex);
				if (m_callbacks.empty()) break;
				cb = std::move(m_callbacks.front());
				m_callbacks.pop();
			}
			cb();
		}
	}

	LRESULT CALLBACK PlatformThread::WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
	{
		if (message == WM_NCCREATE)
		{
			auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
			SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
		}
		else if (message == WM_RUN_DELEGATE)
		{
			auto* self = reinterpret_cast<PlatformThread*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
			if (self) self->Drain();
			return 0;
		}

		return DefWindowProc(hwnd, message, wparam, lparam);
	}
}
