#pragma once

#include <string>

namespace record_windows
{

	struct AudioEncoder
	{
		const std::string aacLc = std::string("aacLc");
		const std::string aacEld = std::string("aacEld");
		const std::string aacHe = std::string("aacHe");
		const std::string amrNb = std::string("amrNb");
		const std::string amrWb = std::string("amrWb");
		const std::string opus = std::string("opus");
		const std::string flac = std::string("flac");
		const std::string pcm16bits = std::string("pcm16bits");
		const std::string wav = std::string("wav");
	};

	struct RecordConfig
	{
		std::string encoderName = AudioEncoder().aacLc;
		std::string deviceId = NULL;
		int bitRate = 128000;
		int sampleRate = 44100;
		int numChannels = 2;
		bool autoGain = false;
		bool echoCancel = false;
		bool noiseSuppress = false;

		RecordConfig(
			const std::string& encoderName,
			const std::string& deviceId,
			int bitRate,
			int sampleRate,
			int numChannels,
			bool autoGain,
			bool echoCancel,
			bool noiseSuppress)
			: encoderName(encoderName),
			deviceId(deviceId),
			bitRate(bitRate),
			sampleRate(sampleRate),
			numChannels(numChannels),
			autoGain(autoGain),
			echoCancel(echoCancel),
			noiseSuppress(noiseSuppress)
		{
		}
	};
};