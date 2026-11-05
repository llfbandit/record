#include "record_config.h"

#include "utils.h"

namespace record_windows
{
	RecordConfig RecordConfig::FromMap(const flutter::EncodableMap& args)
	{
		RecordConfig config;

		GetValueFromEncodableMap(&args, "encoder", config.encoderName);
		GetValueFromEncodableMap(&args, "bitRate", config.bitRate);
		GetValueFromEncodableMap(&args, "sampleRate", config.sampleRate);
		GetValueFromEncodableMap(&args, "numChannels", config.numChannels);
		GetValueFromEncodableMap(&args, "autoGain", config.autoGain);
		GetValueFromEncodableMap(&args, "echoCancel", config.echoCancel);
		GetValueFromEncodableMap(&args, "noiseSuppress", config.noiseSuppress);

		flutter::EncodableMap device;
		if (GetValueFromEncodableMap(&args, "device", device))
		{
			GetValueFromEncodableMap(&device, "id", config.deviceId);
		}
		flutter::EncodableMap win;
		if (GetValueFromEncodableMap(&args, "windowsConfig", win))
		{
			GetValueFromEncodableMap(&win, "captureSystemAudio", config.captureSystemAudio);
			GetValueFromEncodableMap(&win, "micGain", config.micGain);
			GetValueFromEncodableMap(&win, "systemAudioGain", config.systemAudioGain);
		}
		config.rawArgs = args;

		return config;
	}
};
