#include "record_windows.h"

namespace record {
	// Looks for |key| in |map|, returning the associated value if it is present, or
	// a nullptr if not.
	const flutter::EncodableValue* ValueOrNull(const flutter::EncodableMap& map, const char* key) {
		auto it = map.find(flutter::EncodableValue(key));
		if (it == map.end()) {
			return nullptr;
		}
		return &(it->second);
	}

	// static
	void RecordWindowsPlugin::RegisterWithRegistrar(
		flutter::PluginRegistrarWindows* registrar) {
		auto channel =
			std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
				registrar->messenger(), "com.llfbandit.record",
				&flutter::StandardMethodCodec::GetInstance());

		auto plugin = std::make_unique<RecordWindowsPlugin>();

		channel->SetMethodCallHandler(
			[plugin_pointer = plugin.get()](const auto& call, auto result) {
			plugin_pointer->HandleMethodCall(call, std::move(result));
		});

		registrar->AddPlugin(std::move(plugin));
	}

	RecordWindowsPlugin::RecordWindowsPlugin() {}

	RecordWindowsPlugin::~RecordWindowsPlugin() {}

	void RecordWindowsPlugin::HandleMethodCall(
		const flutter::MethodCall<>& method_call,
		std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
		const std::string& method_name = method_call.method_name();

		if (method_name.compare("start") == 0) {
			const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());

			auto samplingRate = GetSamplingRate(*arguments);
			auto path = GetPath(*arguments);
			auto encoderExt = GetEncoderExt(*arguments);

			if (!StartRecording(path, encoderExt, samplingRate)) {
				result->Error("record", "Cannot start recording");
			}
			else {
				result->Success();
			}
		}
		else if (method_name.compare("stop") == 0) {
			std::string path = path_;
			StopRecording();
			result->Success(flutter::EncodableValue(path));
		}
		else if (method_name.compare("pause") == 0) {
			// Not available
			result->Success();
		}
		else if (method_name.compare("resume") == 0) {
			// Not available
			result->Success();
		}
		else if (method_name.compare("isPaused") == 0) {
			result->Success(flutter::EncodableValue(false));
		}
		else if (method_name.compare("isRecording") == 0) {
			result->Success(flutter::EncodableValue(isRecording_));
		}
		else if (method_name.compare("hasPermission") == 0) {
			result->Success(flutter::EncodableValue(true));
		}
		else if (method_name.compare("getAmplitude") == 0) {
			// Not available
			result->Success();
		}
		else if (method_name.compare("isEncoderSupported") == 0) {
			const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
			const auto* encoder = std::get_if<std::string>(ValueOrNull(*arguments, "encoder"));

			if (!encoder) {
				result->Success(flutter::EncodableValue(false));
			}
			else {
				result->Success(flutter::EncodableValue(IsEncoderSupported(*encoder)));
			}			
		}
		else if (method_name.compare("dispose") == 0) {
			StopRecording();
			result->Success();
		}
		else {
			result->NotImplemented();
		}
	}

	bool RecordWindowsPlugin::StartRecording(std::string path, std::string encoderExt, int samplingRate) {
		StopRecording();

		// modify extension to save data with the right encoder
		std::filesystem::path revisedPath = path;
		revisedPath.replace_extension(encoderExt);
		path_ = revisedPath.string();

		if (sf::SoundBufferRecorder::isAvailable()) {
			recorder_ = std::make_shared<sf::SoundBufferRecorder>();

			if (!recorder_->start(samplingRate)) {
				StopRecording();
			}
			else {
				isRecording_ = true;
			}
		}

		return isRecording_;

	}

	void RecordWindowsPlugin::StopRecording() {
		if (recorder_) {
			if (isRecording_) {
				recorder_->stop();

				// Get the buffer containing the captured data
				const sf::SoundBuffer& buffer = recorder_->getBuffer();
				if (!buffer.saveToFile(path_)) {

				}
			}

			recorder_ = nullptr;
		}

		isRecording_ = false;
		path_.clear();
	}

	std::string RecordWindowsPlugin::GenTempFileName() {
		char name[L_tmpnam_s];
		tmpnam_s(name, L_tmpnam_s);
		auto tempPath = std::filesystem::temp_directory_path() / name;

		return tempPath.string();
	}

	std::string RecordWindowsPlugin::GetEncoderExt(const flutter::EncodableMap& args) {
		const auto* encoder = std::get_if<std::string>(ValueOrNull(args, "encoder"));

		if (encoder) {
			if (encoder->compare("wav") == 0) {
				return ".wav";
			}
			else if (encoder->compare("flac") == 0) {
				return ".flac";
			}
			else if (encoder->compare("vorbisOgg") == 0) {
				return ".ogg";
			}
		}

		return ".ogg";
	}

	std::string RecordWindowsPlugin::GetPath(const flutter::EncodableMap& args) {
		const auto* path = std::get_if<std::string>(ValueOrNull(args, "path"));

		if (path) {
			return *path;
		}

		return GenTempFileName();
	}

	int RecordWindowsPlugin::GetSamplingRate(const flutter::EncodableMap& args) {
		const auto* samplingRate = std::get_if<int>(ValueOrNull(args, "samplingRate"));
		
		if (samplingRate) {
			return *samplingRate;
		}

		return 44100;
	}

	bool RecordWindowsPlugin::IsEncoderSupported(std::string encoder) {
		return encoder.compare("wav") == 0 || encoder.compare("flac") == 0 || encoder.compare("vorbisOgg") == 0;
	}
}  // namespace
