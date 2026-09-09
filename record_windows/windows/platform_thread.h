#pragma once

#include <windows.h>

#include <functional>
#include <mutex>
#include <queue>

namespace record_windows
{
	// Flutter's platform thread: MethodResults, EventSinks and channels must be used there.
	class PlatformThread
	{
	public:
		// Platform thread.
		PlatformThread();
		~PlatformThread();

		// Any thread.
		void Post(std::function<void()> callback);

	private:
		static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

		void Drain();

		// Set before other threads can reach it, destroyed after they are joined.
		HWND m_hwnd = NULL;

		std::mutex m_mutex;
		std::queue<std::function<void()>> m_callbacks;
		bool m_wakeupPending = false;
	};
}
