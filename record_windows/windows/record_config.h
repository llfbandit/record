#pragma once

#include <string>

namespace record_windows
{
	struct RecordConfig
	{
		std::string encoderName = "aacLc";
		std::string deviceId = NULL;
		int bitRate = 128000;
		int sampleRate = 44100;
		int numChannels = 2;
		bool autoGain = false;
		bool echoCancel = false;
		bool noiseCancel = false;

		RecordConfig(
			const std::string& encoderName,
			const std::string& deviceId,
			int bitRate,
			int sampleRate,
			int numChannels,
			bool autoGain,
			bool echoCancel,
			bool noiseCancel)
			: encoderName(encoderName),
			deviceId(deviceId),
			bitRate(bitRate),
			sampleRate(sampleRate),
			numChannels(numChannels),
			autoGain(autoGain),
			echoCancel(echoCancel),
			noiseCancel(noiseCancel)
		{
		}
	};
};