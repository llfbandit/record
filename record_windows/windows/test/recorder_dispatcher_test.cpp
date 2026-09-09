#include "recorder_dispatcher.h"

#include <gtest/gtest.h>

#include <atomic>
#include <future>
#include <memory>
#include <thread>
#include <vector>

namespace record_windows
{
	namespace
	{
		// Returns once everything posted before it has run.
		void Flush(RecorderDispatcher& dispatcher)
		{
			std::promise<void> done;
			auto ran = done.get_future();
			if (!dispatcher.Post([&done] { done.set_value(); })) return;
			ran.wait();
		}
	}

	TEST(RecorderDispatcherTest, RunsTasksOffTheCallingThread)
	{
		RecorderDispatcher dispatcher;
		std::thread::id taskThread;

		dispatcher.Post([&taskThread] { taskThread = std::this_thread::get_id(); });
		Flush(dispatcher);

		EXPECT_NE(taskThread, std::this_thread::get_id());
		EXPECT_FALSE(dispatcher.IsCurrentThread());
	}

	// Recorder asserts on this to keep itself lock-free.
	TEST(RecorderDispatcherTest, ReportsItsOwnThread)
	{
		RecorderDispatcher dispatcher;
		bool onDispatcher = false;

		dispatcher.Post([&dispatcher, &onDispatcher] { onDispatcher = dispatcher.IsCurrentThread(); });
		Flush(dispatcher);

		EXPECT_TRUE(onDispatcher);
	}

	// Samples must reach the recorder in capture order.
	TEST(RecorderDispatcherTest, RunsTasksInOrder)
	{
		RecorderDispatcher dispatcher;
		std::vector<int> order;

		for (int i = 0; i < 32; i++) dispatcher.Post([&order, i] { order.push_back(i); });
		Flush(dispatcher);

		ASSERT_EQ(order.size(), 32u);
		for (int i = 0; i < 32; i++) EXPECT_EQ(order[i], i);
	}

	// Start posts a unique_ptr<RecordConfig>, which std::function could not hold.
	TEST(RecorderDispatcherTest, AcceptsMoveOnlyTasks)
	{
		RecorderDispatcher dispatcher;
		auto config = std::make_unique<int>(7);
		int seen = 0;

		dispatcher.Post([&seen, config = std::move(config)] { seen = *config; });
		Flush(dispatcher);

		EXPECT_EQ(seen, 7);
	}

	TEST(RecorderDispatcherTest, RefusesTasksAfterShutdown)
	{
		RecorderDispatcher dispatcher;
		dispatcher.Shutdown();

		EXPECT_FALSE(dispatcher.Post([] {}));
	}

	// A refused task never runs, so the caller has to answer the Dart call itself.
	TEST(RecorderDispatcherTest, RunsWhatWasQueuedBeforeShutdown)
	{
		RecorderDispatcher dispatcher;
		std::atomic<int> ran{ 0 };
		std::promise<void> gate;
		auto opened = gate.get_future();

		// Holds the thread so Shutdown lands with work still queued.
		dispatcher.Post([&opened] { opened.wait(); });
		for (int i = 0; i < 8; i++) dispatcher.Post([&ran] { ran++; });

		dispatcher.Shutdown();
		gate.set_value();
		dispatcher.Join();

		EXPECT_EQ(ran.load(), 8);
	}

	// Teardown answers Dart from here, so the join that follows must find nothing to wait for.
	TEST(RecorderDispatcherTest, RunsExitCallbackAfterEveryTask)
	{
		RecorderDispatcher dispatcher;
		std::vector<int> order;
		bool onDispatcher = false;

		std::promise<void> gate;
		auto opened = gate.get_future();

		// Holds the thread so the batch is queued behind the shutdown, not after it.
		dispatcher.Post([&opened] { opened.wait(); });
		dispatcher.Post([&dispatcher, &order, &onDispatcher] {
			dispatcher.Shutdown([&dispatcher, &order, &onDispatcher] {
				onDispatcher = dispatcher.IsCurrentThread();
				order.push_back(99);
			});
		});
		for (int i = 0; i < 8; i++) dispatcher.Post([&order, i] { order.push_back(i); });

		gate.set_value();
		dispatcher.Join();

		ASSERT_EQ(order.size(), 9u);
		EXPECT_EQ(order.back(), 99);
		EXPECT_TRUE(onDispatcher);
	}

	// RecorderWrapper::Teardown shuts down from inside a task.
	TEST(RecorderDispatcherTest, ShutsDownFromItsOwnThread)
	{
		RecorderDispatcher dispatcher;
		std::atomic<bool> ran{ false };

		dispatcher.Post([&dispatcher, &ran] {
			dispatcher.Shutdown();
			ran = true;
		});
		dispatcher.Join();

		EXPECT_TRUE(ran.load());
		EXPECT_FALSE(dispatcher.Post([] {}));
	}
}
