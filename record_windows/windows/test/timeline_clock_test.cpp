#include "record/timeline_clock.h"

#include <gtest/gtest.h>

namespace record_windows
{
	TEST(TimelineClockTest, FirstSampleStartsFromZero)
	{
		TimelineClock clock;

		LONGLONG ts = 500;
		EXPECT_TRUE(clock.Rebase(ts));
		EXPECT_EQ(ts, 0);
	}

	TEST(TimelineClockTest, LaterSamplesKeepTheirDistance)
	{
		TimelineClock clock;

		LONGLONG first = 500;
		clock.Rebase(first);

		LONGLONG ts = 800;
		EXPECT_FALSE(clock.Rebase(ts));
		EXPECT_EQ(ts, 300);
	}

	// The gap while paused must not show up in the recording.
	TEST(TimelineClockTest, ResumeDropsThePausedGap)
	{
		TimelineClock clock;

		LONGLONG ts = 500;
		clock.Rebase(ts);
		ts = 800;
		clock.Rebase(ts);
		EXPECT_EQ(ts, 300);

		clock.Resume();

		// The device clock moved on by 10000 while nothing was captured.
		ts = 10800;
		EXPECT_TRUE(clock.Rebase(ts));
		EXPECT_EQ(ts, 300);

		ts = 11000;
		EXPECT_FALSE(clock.Rebase(ts));
		EXPECT_EQ(ts, 500);
	}

	// A new device starts its own clock, wherever the old one was.
	TEST(TimelineClockTest, ResumeHandlesADeviceClockGoingBackwards)
	{
		TimelineClock clock;

		LONGLONG ts = 90000;
		clock.Rebase(ts);
		ts = 90300;
		clock.Rebase(ts);

		clock.Resume();

		ts = 40;
		EXPECT_TRUE(clock.Rebase(ts));
		EXPECT_EQ(ts, 300);
	}

	// Paused before any sample arrived: nothing to carry over.
	TEST(TimelineClockTest, ResumeBeforeTheFirstSampleStartsFromZero)
	{
		TimelineClock clock;
		clock.Resume();

		LONGLONG ts = 700;
		EXPECT_TRUE(clock.Rebase(ts));
		EXPECT_EQ(ts, 0);
	}

	TEST(TimelineClockTest, RestartForgetsThePreviousTake)
	{
		TimelineClock clock;

		LONGLONG ts = 500;
		clock.Rebase(ts);
		ts = 800;
		clock.Rebase(ts);

		clock.Restart();

		ts = 2000;
		EXPECT_TRUE(clock.Rebase(ts));
		EXPECT_EQ(ts, 0);
	}

	// A pending Resume() belongs to the take that just ended.
	TEST(TimelineClockTest, RestartDropsAPendingResume)
	{
		TimelineClock clock;

		LONGLONG ts = 500;
		clock.Rebase(ts);
		clock.Resume();
		clock.Restart();

		ts = 2000;
		EXPECT_TRUE(clock.Rebase(ts));
		EXPECT_EQ(ts, 0);
	}
}
