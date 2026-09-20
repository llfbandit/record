#include "record_config.h"

#include <gtest/gtest.h>

namespace record_windows
{
	namespace
	{
		flutter::EncodableValue Key(const char* name)
		{
			return flutter::EncodableValue(name);
		}
	}

	TEST(RecordConfigTest, FromMapReadsEveryField)
	{
		flutter::EncodableMap args{
			{ Key("encoder"),       flutter::EncodableValue(AudioEncoder::wav) },
			{ Key("bitRate"),       flutter::EncodableValue(64000) },
			{ Key("sampleRate"),    flutter::EncodableValue(16000) },
			{ Key("numChannels"),   flutter::EncodableValue(1) },
			{ Key("autoGain"),      flutter::EncodableValue(true) },
			{ Key("echoCancel"),    flutter::EncodableValue(true) },
			{ Key("noiseSuppress"), flutter::EncodableValue(true) },
			{ Key("device"), flutter::EncodableValue(flutter::EncodableMap{
				{ Key("id"), flutter::EncodableValue("endpoint-1") },
			}) },
		};

		auto config = RecordConfig::FromMap(args);

		EXPECT_EQ(config.encoderName, AudioEncoder::wav);
		EXPECT_EQ(config.bitRate, 64000);
		EXPECT_EQ(config.sampleRate, 16000);
		EXPECT_EQ(config.numChannels, 1);
		EXPECT_TRUE(config.autoGain);
		EXPECT_TRUE(config.echoCancel);
		EXPECT_TRUE(config.noiseSuppress);
		EXPECT_EQ(config.deviceId, "endpoint-1");
	}

	// A missing key used to leave the field uninitialized.
	TEST(RecordConfigTest, FromMapKeepsDefaultsOnAnEmptyMap)
	{
		auto config = RecordConfig::FromMap(flutter::EncodableMap());

		EXPECT_EQ(config.encoderName, AudioEncoder::aacLc);
		EXPECT_EQ(config.bitRate, 128000);
		EXPECT_EQ(config.sampleRate, 44100);
		EXPECT_EQ(config.numChannels, 2);
		EXPECT_FALSE(config.autoGain);
		EXPECT_FALSE(config.echoCancel);
		EXPECT_FALSE(config.noiseSuppress);
		EXPECT_TRUE(config.deviceId.empty());
	}

	// Dart sends null for a device left unset.
	TEST(RecordConfigTest, FromMapKeepsDefaultsOnNullValues)
	{
		flutter::EncodableMap args{
			{ Key("device"),  flutter::EncodableValue() },
			{ Key("bitRate"), flutter::EncodableValue() },
		};

		auto config = RecordConfig::FromMap(args);

		EXPECT_TRUE(config.deviceId.empty());
		EXPECT_EQ(config.bitRate, 128000);
	}

	// The raw map is forwarded back to Dart on a config change.
	TEST(RecordConfigTest, FromMapKeepsTheRawArguments)
	{
		flutter::EncodableMap args{
			{ Key("sampleRate"), flutter::EncodableValue(48000) },
		};

		auto config = RecordConfig::FromMap(args);

		EXPECT_EQ(config.rawArgs.size(), args.size());
		EXPECT_EQ(config.rawArgs.at(Key("sampleRate")), flutter::EncodableValue(48000));
	}
}
