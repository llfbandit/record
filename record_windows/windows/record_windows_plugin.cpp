#include "record_windows_plugin.h"
#include "audio_device/record_audio_device.h"
#include "record_config.h"
#include <exception>
#include <mutex>

using namespace flutter;

namespace record_windows {
	typedef std::shared_ptr<MethodResult<EncodableValue>> SharedResult;

	static void ErrorFromHR(HRESULT hr, MethodResult<EncodableValue>& result)
	{
		_com_error err(hr);
		std::string errorText = Utf8FromUtf16(err.ErrorMessage());

		result.Error("Record", "", EncodableValue(errorText));
	}

	// Answers a call that has no value.
	static RecorderWrapper::Reply HrReply(SharedResult result, std::shared_ptr<bool> alive)
	{
		return [result, alive](HRESULT hr) {
			if (!*alive) return;
			if (SUCCEEDED(hr)) { result->Success(EncodableValue()); }
			else { ErrorFromHR(hr, *result); }
		};
	}

	// static, Register the plugin
	void RecordWindowsPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
		auto plugin = std::make_unique<RecordWindowsPlugin>(registrar->messenger());

		auto methodChannel = std::make_unique<MethodChannel<EncodableValue>>(
			registrar->messenger(), "com.llfbandit.record/messages",
			&StandardMethodCodec::GetInstance());

		methodChannel->SetMethodCallHandler(
			[plugin_pointer = plugin.get()](const auto& call, auto result)
			{
				plugin_pointer->HandleMethodCall(call, std::move(result));
			});

		registrar->AddPlugin(std::move(plugin));
	}

	RecordWindowsPlugin::RecordWindowsPlugin(BinaryMessenger* messenger)
		: m_binaryMessenger(messenger) {
	}

	RecordWindowsPlugin::~RecordWindowsPlugin() {
		*m_alive = false;

		// Each one joins its thread, so nothing posts to m_platform afterwards.
		m_recorders.clear();
	}

	// Called when a method is called on this plugin's channel from Dart.
	void RecordWindowsPlugin::HandleMethodCall(
		const MethodCall<EncodableValue>& method_call,
		std::unique_ptr<MethodResult<EncodableValue>> result
	) {
		const auto args = method_call.arguments();
		const auto* mapArgs = std::get_if<EncodableMap>(args);
		if (!mapArgs) {
			result->Error("Record", "Call missing parameters");
			return;
		}

		std::string recorderId;
		GetValueFromEncodableMap(mapArgs, "recorderId", recorderId);
		if (recorderId.empty()) {
			result->Error("Record", "Call missing mandatory parameter recorderId");
			return;
		}

		if (method_call.method_name().compare("create") == 0) {
			try {
				CreateRecorder(recorderId);
				result->Success(EncodableValue(NULL));
			}
			catch (const std::exception& e) {
				result->Error("Record", e.what());
			}			
			return;
		}

		auto recorder = GetRecorder(recorderId);
		if (!recorder) {
			result->Error(
				"Record",
				"Recorder has not yet been created or has already been disposed."
			);
			return;
		}

		SharedResult shared(std::move(result));
		auto alive = m_alive;

		if (method_call.method_name().compare("hasPermission") == 0)
		{
			shared->Success(EncodableValue(true));
		}
		else if (method_call.method_name().compare("isPaused") == 0)
		{
			recorder->IsPaused([shared, alive](bool paused) {
				if (*alive) shared->Success(EncodableValue(paused));
			});
		}
		else if (method_call.method_name().compare("isRecording") == 0)
		{
			recorder->IsRecording([shared, alive](bool recording) {
				if (*alive) shared->Success(EncodableValue(recording));
			});
		}
		else if (method_call.method_name().compare("pause") == 0)
		{
			recorder->Pause(HrReply(shared, alive));
		}
		else if (method_call.method_name().compare("resume") == 0)
		{
			recorder->Resume(HrReply(shared, alive));
		}
		else if (method_call.method_name().compare("start") == 0)
		{
			auto config = InitRecordConfig(mapArgs);

			std::string path;
			GetValueFromEncodableMap(mapArgs, "path", path);

			recorder->Start(std::move(config), Utf16FromUtf8(path), HrReply(shared, alive));
		}
		else if (method_call.method_name().compare("startStream") == 0)
		{
			auto config = InitRecordConfig(mapArgs);

			recorder->StartStream(std::move(config), HrReply(shared, alive));
		}
		else if (method_call.method_name().compare("stop") == 0)
		{
			recorder->Stop([shared, alive](StopResult r) {
				if (!*alive) return;
				if (SUCCEEDED(r.hr))
				{
					shared->Success(r.path.empty() ? EncodableValue() : EncodableValue(Utf8FromUtf16(r.path.c_str())));
				}
				else {
					ErrorFromHR(r.hr, *shared);
				}
			});
		}
		else if (method_call.method_name().compare("cancel") == 0)
		{
			recorder->Cancel(HrReply(shared, alive));
		}
		else if (method_call.method_name().compare("dispose") == 0)
		{
			recorder->Dispose([this, shared, alive, recorderId] {
				if (!*alive) return;
				m_recorders.erase(recorderId);
				shared->Success(EncodableValue());
			});
		}
		else if (method_call.method_name().compare("getAmplitude") == 0)
		{
			recorder->GetAmplitude([shared, alive](std::map<std::string, double> amp) {
				if (!*alive) return;
				shared->Success(EncodableValue(
					EncodableMap({
						{EncodableValue("current"), EncodableValue(amp["current"])},
						{EncodableValue("max"), EncodableValue(amp["max"])}
						}
					))
				);
			});
		}
		else if (method_call.method_name().compare("isEncoderSupported") == 0)
		{
			std::string encoderName;
			if (!GetValueFromEncodableMap(mapArgs, "encoder", encoderName))
			{
				shared->Error("Bad arguments", "Expected encoder name.");
				return;
			}

			bool supported = false;
			HRESULT hr = AudioDevice::IsEncoderSupported(encoderName, &supported);

			if (SUCCEEDED(hr))
			{
				shared->Success(EncodableValue(supported));
			}
			else
			{
				ErrorFromHR(hr, *shared);
			}
		}
		else if (method_call.method_name().compare("listInputDevices") == 0)
		{
			EncodableList devices;
			HRESULT hr = AudioDevice::ListInputDevices(devices);
			if (SUCCEEDED(hr)) {
				shared->Success(EncodableValue(std::move(devices)));
			} else {
				ErrorFromHR(hr, *shared);
			}
		}
	}

	std::unique_ptr<RecordConfig> RecordWindowsPlugin::InitRecordConfig(const EncodableMap* args)
	{
		std::string path;
		GetValueFromEncodableMap(args, "path", path);
		std::string encoderName;
		GetValueFromEncodableMap(args, "encoder", encoderName);
		int bitRate;
		GetValueFromEncodableMap(args, "bitRate", bitRate);
		int sampleRate;
		GetValueFromEncodableMap(args, "sampleRate", sampleRate);
		int numChannels;
		GetValueFromEncodableMap(args, "numChannels", numChannels);
		EncodableMap device;
		std::string deviceId;
		if (GetValueFromEncodableMap(args, "device", device))
		{
			GetValueFromEncodableMap(&device, "id", deviceId);
		}
		bool autoGain;
		GetValueFromEncodableMap(args, "autoGain", autoGain);
		bool echoCancel;
		GetValueFromEncodableMap(args, "echoCancel", echoCancel);
		bool noiseSuppress;
		GetValueFromEncodableMap(args, "noiseSuppress", noiseSuppress);

		auto config = std::make_unique<RecordConfig>(
			encoderName,
			deviceId,
			bitRate,
			sampleRate,
			numChannels,
			autoGain,
			echoCancel,
			noiseSuppress,
			*args
		);

		return config;
	}

	void RecordWindowsPlugin::CreateRecorder(std::string recorderId)
	{
		// Warmup codec capabilities since this is quite slow. This is done only once for all instances.
		static std::once_flag sWarmFlag;
		std::call_once(sWarmFlag, [] { AudioDevice::WarmCodecCapsAsync(); });

		if (m_recorders.find(recorderId) == m_recorders.end())
		{
			auto recorder = std::make_unique<RecorderWrapper>(m_binaryMessenger, recorderId, m_platform);
			m_recorders[recorderId] = std::move(recorder);
		}
	}

	RecorderWrapper* RecordWindowsPlugin::GetRecorder(std::string recorderId)
	{
		auto searchedRecorder = m_recorders.find(recorderId);
		if (searchedRecorder == m_recorders.end()) {
			return nullptr;
		}
		return searchedRecorder->second.get();
	}

}  // namespace record_windows
