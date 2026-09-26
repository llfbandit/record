#pragma once

#include <string>
#include <flutter/encodable_value.h>

namespace record_windows
{

	struct AudioEncoder
	{
		static constexpr const char* aacLc     = "aacLc";
		static constexpr const char* aacEld    = "aacEld";
		static constexpr const char* aacHe     = "aacHe";
		static constexpr const char* amrNb     = "amrNb";
		static constexpr const char* amrWb     = "amrWb";
		static constexpr const char* opus      = "opus";
		static constexpr const char* flac      = "flac";
		static constexpr const char* pcm16bits = "pcm16bits";
		static constexpr const char* wav       = "wav";
	};

	// Picks what the recorder does when the input device in use goes away.
	enum class AudioRouteChange
	{
		follow = 0, pause = 1, stop = 2
	};

	// An unknown value (a newer Dart side) keeps the safe default.
	constexpr AudioRouteChange ToAudioRouteChange(int value)
	{
		switch (value)
		{
		case 0:  return AudioRouteChange::follow;
		case 2:  return AudioRouteChange::stop;
		default: return AudioRouteChange::pause;
		}
	}

	struct RecordConfig
	{
		std::string encoderName = AudioEncoder::aacLc;
		std::string deviceId = {};
		int bitRate = 128000;
		int sampleRate = 44100;
		int numChannels = 2;
		bool autoGain = false;
		bool echoCancel = false;
		bool noiseSuppress = false;
		AudioRouteChange audioRouteChange = AudioRouteChange::pause;
		flutter::EncodableMap rawArgs;

		// Reads the Dart call arguments. A missing key keeps the default above.
		static RecordConfig FromMap(const flutter::EncodableMap& args);

		RecordConfig() = default;

		RecordConfig(
			const std::string& encoderName,
			const std::string& deviceId,
			int bitRate,
			int sampleRate,
			int numChannels,
			bool autoGain,
			bool echoCancel,
			bool noiseSuppress,
			AudioRouteChange audioRouteChange,
			flutter::EncodableMap rawArgs)
			: encoderName(encoderName),
			deviceId(deviceId),
			bitRate(bitRate),
			sampleRate(sampleRate),
			numChannels(numChannels),
			autoGain(autoGain),
			echoCancel(echoCancel),
			noiseSuppress(noiseSuppress),
			audioRouteChange(audioRouteChange),
			rawArgs(std::move(rawArgs))
		{
		}
	};
};