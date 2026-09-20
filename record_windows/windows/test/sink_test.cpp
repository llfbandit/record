#include "record/sink/file_sink.h"
#include "record/sink/stream_sink.h"

#include <gtest/gtest.h>

#include <fstream>
#include <string>

namespace record_windows
{
	namespace
	{
		std::wstring TempPath(const wchar_t* name)
		{
			wchar_t temp[MAX_PATH];
			GetTempPathW(MAX_PATH, temp);

			return std::wstring(temp) + name;
		}

		bool Exists(const std::wstring& path)
		{
			return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
		}
	}

	TEST(StreamSinkTest, SupportsTheStreamableEncoders)
	{
		EXPECT_TRUE(StreamSink::Supports(AudioEncoder::aacLc));
		EXPECT_TRUE(StreamSink::Supports(AudioEncoder::pcm16bits));
	}

	// A container format can't be handed out chunk by chunk.
	TEST(StreamSinkTest, RejectsTheOtherEncoders)
	{
		EXPECT_FALSE(StreamSink::Supports(AudioEncoder::wav));
		EXPECT_FALSE(StreamSink::Supports(AudioEncoder::flac));
		EXPECT_FALSE(StreamSink::Supports(AudioEncoder::opus));
		EXPECT_FALSE(StreamSink::Supports(""));
	}

	// Stop() answers with it, so it must be known before the take ends.
	TEST(FileSinkTest, ReportsItsPathBeforeOpening)
	{
		FileSink sink(L"C:\\takes\\one.wav");

		EXPECT_EQ(sink.Path(), L"C:\\takes\\one.wav");
	}

	// Nothing to hand out: the take is streamed.
	TEST(StreamSinkTest, HasNoPath)
	{
		StreamSink sink(nullptr);

		EXPECT_TRUE(sink.Path().empty());
	}

	TEST(FileSinkTest, DiscardRemovesTheFile)
	{
		auto path = TempPath(L"record_file_sink_test.wav");
		{
			std::ofstream file(path.c_str(), std::ios::binary);
			file << "take";
		}
		ASSERT_TRUE(Exists(path));

		FileSink(path).Discard();

		EXPECT_FALSE(Exists(path));
	}

	// Cancel() before anything was written must not throw.
	TEST(FileSinkTest, DiscardIgnoresAMissingFile)
	{
		auto path = TempPath(L"record_file_sink_missing.wav");
		DeleteFileW(path.c_str());

		FileSink(path).Discard();

		EXPECT_FALSE(Exists(path));
	}

	// A failed open must not leave an empty file behind.
	TEST(FileSinkTest, OpenLeavesNoFileBehindWhenItFails)
	{
		auto path = TempPath(L"record_file_sink_failed_open.wav");
		DeleteFileW(path.c_str());

		CoInitializeEx(nullptr, COINIT_MULTITHREADED);
		ASSERT_HRESULT_SUCCEEDED(MFStartup(MF_VERSION));

		FileSink sink(path);
		RecordConfig config;
		config.encoderName = "not_an_encoder";

		EXPECT_HRESULT_FAILED(sink.Open(config, nullptr));
		EXPECT_FALSE(Exists(path));

		MFShutdown();
		CoUninitialize();
	}

	// A take that failed to open still gets finalized on the way out.
	TEST(FileSinkTest, FinalizeSucceedsWithoutAWriter)
	{
		FileSink sink(TempPath(L"record_file_sink_unopened.raw"));

		EXPECT_HRESULT_SUCCEEDED(sink.Finalize());
	}

	TEST(StreamSinkTest, FinalizeSucceedsWithoutAnEncoder)
	{
		StreamSink sink(nullptr);

		EXPECT_HRESULT_SUCCEEDED(sink.Finalize());
	}
}
