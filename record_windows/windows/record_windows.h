#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <sstream>
#include <filesystem>
#include <stdio.h>

#include <SFML/Audio.hpp>

namespace record {
	class RecordWindowsPlugin : public flutter::Plugin {
	public:
		static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

		RecordWindowsPlugin();

		virtual ~RecordWindowsPlugin();

	private:
		// Called when a method is called on this plugin's channel from Dart.
		void HandleMethodCall(
			const flutter::MethodCall<flutter::EncodableValue>& method_call,
			std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

		bool StartRecording(std::string path, std::string encoderExt, int samplingRate);
		void StopRecording();		

		std::string GetEncoderExt(const flutter::EncodableMap& args);
		std::string GetPath(const flutter::EncodableMap& args);
		int GetSamplingRate(const flutter::EncodableMap& args);
		bool IsEncoderSupported(std::string encoder);
		std::string GenTempFileName();

		std::shared_ptr<sf::SoundBufferRecorder> recorder_;
		bool isRecording_ = false;
		std::string path_;
	};
}
