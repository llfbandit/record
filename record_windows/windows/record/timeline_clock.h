#pragma once

#include <windows.h>

namespace record_windows
{
	// Keeps sample timestamps continuous across pause/resume and device swaps.
	class TimelineClock
	{
	public:
		// The next sample opens a new take, from zero.
		void Restart()
		{
			m_first    = true;
			m_resuming = false;
			m_base     = 0;
			m_last     = 0;
		}

		// The next sample carries on the take after a gap.
		void Resume() { m_resuming = true; }

		// Shifts llTimestamp onto the take timeline.
		// Returns true when this sample is the one capture (re)starts on.
		bool Rebase(LONGLONG& llTimestamp)
		{
			bool started = false;

			if (m_first)
			{
				m_first    = false;
				// Paused before any sample arrived: treat as a fresh start.
				m_resuming = false;
				m_base     = llTimestamp;
				started    = true;
			}
			else if (m_resuming)
			{
				m_resuming = false;
				// Shift base so timestamps resume from the pause instead of jumping back.
				m_base     = llTimestamp - (m_last - m_base);
				started    = true;
			}

			m_last = llTimestamp;
			llTimestamp -= m_base;

			return started;
		}

	private:
		bool     m_first    = true;
		bool     m_resuming = false;
		LONGLONG m_base     = 0;
		LONGLONG m_last     = 0;
	};
}
