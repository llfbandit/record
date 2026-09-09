#pragma once

#include <windows.h>
#include <mfapi.h>

#include <cassert>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <queue>
#include <thread>
#include <type_traits>
#include <utility>

namespace record_windows
{
	// The one thread a recorder's state is touched from.
	class RecorderDispatcher
	{
	public:
		RecorderDispatcher() : m_thread([this] { Run(); }) {}

		~RecorderDispatcher()
		{
			Shutdown();
			Join();
		}

		// Returns false once shut down; the task is then dropped.
		template <typename F>
		bool Post(F&& task)
		{
			{
				std::lock_guard<std::mutex> lock(m_mutex);
				if (m_stopped) return false;
				m_queue.push(std::make_unique<Task<std::decay_t<F>>>(std::forward<F>(task)));
			}
			m_cv.notify_one();
			return true;
		}

		// Refuses new tasks; queued ones still run, then the thread exits.
		// onExit runs last on this thread: post it from a task, or it may never run.
		void Shutdown(std::function<void()> onExit = nullptr)
		{
			assert(!onExit || IsCurrentThread());
			{
				std::lock_guard<std::mutex> lock(m_mutex);
				m_stopped = true;
				if (onExit) m_onExit = std::move(onExit);
			}
			m_cv.notify_one();
		}

		void Join()
		{
			if (m_thread.joinable()) m_thread.join();
		}

		bool IsCurrentThread() const
		{
			return std::this_thread::get_id() == m_thread.get_id();
		}

	private:
		// std::function needs copyable callables; posted lambdas move unique_ptrs in.
		struct TaskBase
		{
			virtual ~TaskBase() = default;
			virtual void Run() = 0;
		};

		template <typename F>
		struct Task : TaskBase
		{
			F f;
			template <typename G>
			explicit Task(G&& g) : f(std::forward<G>(g)) {}
			void Run() override { f(); }
		};

		void Run()
		{
			// MMDevice and Media Foundation objects are created and used on this thread only.
			CoInitializeEx(nullptr, COINIT_MULTITHREADED);
			// Spans every take: a queued sample must not be released after shutdown.
			MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET);

			for (;;)
			{
				std::unique_ptr<TaskBase> task;
				{
					std::unique_lock<std::mutex> lock(m_mutex);
					m_cv.wait(lock, [this] { return m_stopped || !m_queue.empty(); });
					if (m_queue.empty()) break;
					task = std::move(m_queue.front());
					m_queue.pop();
				}
				task->Run();
			}

			// The queue is drained: every sample and MF object is already released.
			MFShutdown();
			CoUninitialize();

			// Last, so whoever it wakes finds nothing left to wait for.
			std::function<void()> onExit;
			{
				std::lock_guard<std::mutex> lock(m_mutex);
				onExit = std::move(m_onExit);
			}
			if (onExit) onExit();
		}

		std::mutex m_mutex;
		std::condition_variable m_cv;
		std::queue<std::unique_ptr<TaskBase>> m_queue;
		std::function<void()> m_onExit;
		bool m_stopped = false;
		// Last: the thread starts here and uses the members above.
		std::thread m_thread;
	};
}
