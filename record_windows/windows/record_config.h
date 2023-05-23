#pragma once

#include <string>

namespace record_windows
{
	struct RecordConfig
	{
		std::string encoderName = "aacLc";
		std::string deviceId = NULL;
		int bitRate = 128000;
		int samplingRate = 44100;
		int numChannels = 2;
		bool autoGain = false;
		bool echoCancel = false;
		bool noiseCancel = false;

		RecordConfig(
			const std::string& encoderName,
			const std::string& deviceId,
			int bitRate,
			int samplingRate,
			int numChannels,
			bool autoGain,
			bool echoCancel,
			bool noiseCancel)
			: encoderName(encoderName),
			deviceId(deviceId),
			bitRate(bitRate),
			samplingRate(samplingRate),
			numChannels(numChannels),
			autoGain(autoGain),
			echoCancel(echoCancel),
			noiseCancel(noiseCancel)
		{
		}
	};
};