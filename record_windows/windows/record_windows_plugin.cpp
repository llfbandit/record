#include "record_windows_plugin.h"
#include "record_config.h"
#include <flutter/event_stream_handler_functions.h>
#include <mmdeviceapi.h>
#include <functiondiscoverykeys_devpkey.h>
#include <propvarutil.h>

using namespace flutter;

namespace record_windows {
	static void ErrorFromHR(HRESULT hr, MethodResult<EncodableValue>& result)
	{
		_com_error err(hr);
		std::string errorText = Utf8FromUtf16(err.ErrorMessage());
		
		// Add more specific error messages for common WASAPI errors
		std::string specificError = "Unknown error";
		switch (hr)
		{
		case AUDCLNT_E_DEVICE_INVALIDATED:
			specificError = "Audio device was removed or became unavailable";
			break;
		case AUDCLNT_E_NOT_INITIALIZED:
			specificError = "Audio client not initialized";
			break;
		case AUDCLNT_E_ALREADY_INITIALIZED:
			specificError = "Audio client already initialized";
			break;
		case AUDCLNT_E_DEVICE_IN_USE:
			specificError = "Audio device is in use by another application";
			break;
		case E_ACCESSDENIED:
			specificError = "Access denied - check microphone permissions in Windows Settings";
			break;
		case AUDCLNT_E_UNSUPPORTED_FORMAT:
			specificError = "Requested audio format is not supported";
			break;
		case AUDCLNT_E_EXCLUSIVE_MODE_NOT_ALLOWED:
			specificError = "Exclusive audio mode not allowed";
			break;
		case 0x88890008: // AUDCLNT_E_ENDPOINT_CREATE_FAILED
			specificError = "Audio endpoint creation failed - no microphone available";
			break;
		case E_INVALIDARG:
			specificError = "Invalid argument provided";
			break;
		case E_OUTOFMEMORY:
			specificError = "Out of memory";
			break;
		default:
			specificError = "Error code 0x" + std::to_string(hr);
			break;
		}

		result.Error("Record", specificError, EncodableValue(errorText));
	}

	static HWND GetRootWindow(flutter::FlutterView* view) {
		return ::GetAncestor(view->GetNativeWindow(), GA_ROOT);
	}

	// static, Register the plugin
	void RecordWindowsPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
		auto plugin = std::make_unique<RecordWindowsPlugin>(
			[registrar](auto delegate) {
				return registrar->RegisterTopLevelWindowProcDelegate(delegate);
			},
			[registrar](auto proc_id) {
				registrar->UnregisterTopLevelWindowProcDelegate(proc_id);
			},
			[registrar] { return GetRootWindow(registrar->GetView()); }
		);

		m_binaryMessenger = registrar->messenger();

		auto methodChannel = std::make_unique<MethodChannel<EncodableValue>>(
			m_binaryMessenger, "com.llfbandit.record/messages",
			&StandardMethodCodec::GetInstance());

		methodChannel->SetMethodCallHandler(
			[plugin_pointer = plugin.get()](const auto& call, auto result)
			{
				plugin_pointer->HandleMethodCall(call, std::move(result));
			});

		registrar->AddPlugin(std::move(plugin));
	}

	// static
	std::queue<std::function<void()>> RecordWindowsPlugin::callbacks{};

	// static
	FlutterRootWindowProvider RecordWindowsPlugin::get_root_window{};

	// static
	void RecordWindowsPlugin::RunOnMainThread(std::function<void()> callback) {
		callbacks.push(callback);
		PostMessage(get_root_window(), WM_RUN_DELEGATE, 0, 0);
	}

	RecordWindowsPlugin::RecordWindowsPlugin(
		WindowProcDelegateRegistrator registrator,
		WindowProcDelegateUnregistrator unregistrator,
		FlutterRootWindowProvider window_provider
	):	m_win_proc_delegate_registrator(registrator),
		m_win_proc_delegate_unregistrator(unregistrator) {

		get_root_window = std::move(window_provider);

		m_window_proc_id = m_win_proc_delegate_registrator(
			[this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
				return HandleWindowProc(hwnd, message, wparam, lparam);
			}
		);
	}

	RecordWindowsPlugin::~RecordWindowsPlugin() {
		for (const auto& [recorderId, recorder] : m_recorders)
		{
			recorder->Dispose();
		}

		m_win_proc_delegate_unregistrator(m_window_proc_id);
	}

	std::optional<LRESULT> RecordWindowsPlugin::HandleWindowProc(HWND hwnd,
		UINT message,
		WPARAM wparam,
		LPARAM lparam) {
		std::optional<LRESULT> result;
		switch (message) {
		case WM_RUN_DELEGATE:
			callbacks.front()();
			callbacks.pop();
			result = 0;
			break;
		}
		return result;
	}

	// Called when a method is called on this plugin's channel from Dart.
	void RecordWindowsPlugin::RecordWindowsPlugin::HandleMethodCall(
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
			HRESULT hr = CreateRecorder(recorderId);

			if (SUCCEEDED(hr)) {
				result->Success(EncodableValue(NULL));
			}
			else {
				ErrorFromHR(hr, *result);
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

		if (method_call.method_name().compare("hasPermission") == 0)
		{
			result->Success(EncodableValue(true));
		}
		else if (method_call.method_name().compare("isPaused") == 0)
		{
			result->Success(EncodableValue(recorder->IsPaused()));
		}
		else if (method_call.method_name().compare("isRecording") == 0)
		{
			result->Success(EncodableValue(recorder->IsRecording()));
		}
		else if (method_call.method_name().compare("pause") == 0)
		{
			HRESULT hr = recorder->Pause();

			if (SUCCEEDED(hr)) { result->Success(EncodableValue()); }
			else { ErrorFromHR(hr, *result); }
		}
		else if (method_call.method_name().compare("resume") == 0)
		{
			HRESULT hr = recorder->Resume();

			if (SUCCEEDED(hr)) { result->Success(EncodableValue()); }
			else { ErrorFromHR(hr, *result); }
		}
		else if (method_call.method_name().compare("start") == 0)
		{
			auto config = InitRecordConfig(mapArgs);

			std::string path;
			GetValueFromEncodableMap(mapArgs, "path", path);

			HRESULT hr = recorder->Start(std::move(config), Utf16FromUtf8(path));

			if (SUCCEEDED(hr)) { result->Success(EncodableValue()); }
			else { ErrorFromHR(hr, *result); }
		}
		else if (method_call.method_name().compare("startStream") == 0)
		{
			auto config = InitRecordConfig(mapArgs);

			HRESULT hr = recorder->StartStream(std::move(config));

			if (SUCCEEDED(hr)) { result->Success(EncodableValue()); }
			else { ErrorFromHR(hr, *result); }
		}
		else if (method_call.method_name().compare("stop") == 0)
		{
			auto recordingPath = recorder->GetRecordingPath();
			HRESULT hr = recorder->Stop();

			if (SUCCEEDED(hr))
			{
				result->Success(recordingPath.empty() ? EncodableValue() : EncodableValue(Utf8FromUtf16(recordingPath)));
			}
			else {
				ErrorFromHR(hr, *result);
			}
		}
		else if (method_call.method_name().compare("cancel") == 0)
		{
			HRESULT hr = recorder->Cancel();

			if (SUCCEEDED(hr))
			{
				result->Success(EncodableValue());
			}
			else
			{
				ErrorFromHR(hr, *result);
			}
		}
		else if (method_call.method_name().compare("dispose") == 0)
		{
			recorder->Dispose();
			m_recorders.erase(recorderId);

			result->Success(EncodableValue());
		}
		else if (method_call.method_name().compare("getAmplitude") == 0)
		{
			auto amp = recorder->GetAmplitude();

			result->Success(EncodableValue(
				EncodableMap({
					{EncodableValue("current"), EncodableValue(amp["current"])},
					{EncodableValue("max"), EncodableValue(amp["max"])}
					}
				))
			);
		}
		else if (method_call.method_name().compare("isEncoderSupported") == 0)
		{
			std::string encoderName;
			if (!GetValueFromEncodableMap(mapArgs, "encoder", encoderName))
			{
				result->Error("Bad arguments", "Expected encoder name.");
				return;
			}

			bool supported = false;
			HRESULT hr = recorder->isEncoderSupported(encoderName, &supported);

			if (SUCCEEDED(hr))
			{
				result->Success(EncodableValue(supported));
			}
			else
			{
				ErrorFromHR(hr, *result);
			}
		}
		else if (method_call.method_name().compare("listInputDevices") == 0)
		{
			ListInputDevices(*result);
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
			noiseSuppress
		);

		return config;
	}

	HRESULT RecordWindowsPlugin::CreateRecorder(std::string recorderId)
	{
		// State event channel
		auto eventChannel = std::make_unique<EventChannel<EncodableValue>>(
			m_binaryMessenger, "com.llfbandit.record/events/" + recorderId,
			&StandardMethodCodec::GetInstance());

		auto eventHandler = new EventStreamHandler<>();
		std::unique_ptr<StreamHandler<EncodableValue>> pStateEventHandler{static_cast<StreamHandler<EncodableValue>*>(eventHandler)};
		eventChannel->SetStreamHandler(std::move(pStateEventHandler));

		// Record stream event channel
		auto eventRecordChannel = std::make_unique<EventChannel<EncodableValue>>(
			m_binaryMessenger, "com.llfbandit.record/eventsRecord/" + recorderId,
			&StandardMethodCodec::GetInstance());

		auto eventRecordHandler = new EventStreamHandler<>();
		std::unique_ptr<StreamHandler<EncodableValue>> pRecordEventHandler{static_cast<StreamHandler<EncodableValue>*>(eventRecordHandler)};
		eventRecordChannel->SetStreamHandler(std::move(pRecordEventHandler));

		Recorder* pRecorder = NULL;

		HRESULT hr = Recorder::CreateInstance(eventHandler, eventRecordHandler, &pRecorder);
		if (SUCCEEDED(hr))
		{
			m_recorders.insert(std::make_pair(recorderId, std::move(pRecorder)));
		}

		return hr;
	}

	Recorder* RecordWindowsPlugin::GetRecorder(std::string recorderId)
	{
		auto searchedRecorder = m_recorders.find(recorderId);
		if (searchedRecorder == m_recorders.end()) {
			return nullptr;
		}
		return searchedRecorder->second.get();
	}

	HRESULT RecordWindowsPlugin::ListInputDevices(MethodResult<EncodableValue>& result)
	{
		EncodableList devices;
		HRESULT hr = S_OK;

		// Initialize COM if not already done
		CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

		IMMDeviceEnumerator* pEnumerator = nullptr;
		IMMDeviceCollection* pCollection = nullptr;

		// Create device enumerator
		hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
							  __uuidof(IMMDeviceEnumerator), 
							  reinterpret_cast<void**>(&pEnumerator));

		if (SUCCEEDED(hr))
		{
			// Get collection of audio capture devices
			hr = pEnumerator->EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, &pCollection);
		}

		UINT deviceCount = 0;
		if (SUCCEEDED(hr))
		{
			hr = pCollection->GetCount(&deviceCount);
		}

		// Enumerate through each device
		for (UINT i = 0; i < deviceCount && SUCCEEDED(hr); i++)
		{
			IMMDevice* pDevice = nullptr;
			hr = pCollection->Item(i, &pDevice);

			if (SUCCEEDED(hr))
			{
				// Get device ID
				LPWSTR deviceId = nullptr;
				hr = pDevice->GetId(&deviceId);

				if (SUCCEEDED(hr))
				{
					// Get device friendly name
					IPropertyStore* pProps = nullptr;
					hr = pDevice->OpenPropertyStore(STGM_READ, &pProps);

					if (SUCCEEDED(hr))
					{
						PROPVARIANT friendlyName;
						PropVariantInit(&friendlyName);

						hr = pProps->GetValue(PKEY_Device_FriendlyName, &friendlyName);

						if (SUCCEEDED(hr) && friendlyName.vt == VT_LPWSTR)
						{
							devices.push_back(EncodableMap({
								{EncodableValue("id"), EncodableValue(toString(deviceId))},
								{EncodableValue("label"), EncodableValue(toString(friendlyName.pwszVal))}
							}));
						}

						PropVariantClear(&friendlyName);
						pProps->Release();
					}

					CoTaskMemFree(deviceId);
				}

				pDevice->Release();
			}
		}

		if (SUCCEEDED(hr))
		{
			result.Success(std::move(EncodableValue(devices)));
		}
		else
		{
			ErrorFromHR(hr, result);
		}

		if (pCollection) pCollection->Release();
		if (pEnumerator) pEnumerator->Release();

		return hr;
	}
}  // namespace record_windows
