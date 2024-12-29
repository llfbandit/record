#ifndef FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_


#include <flutter/plugin_registrar_windows.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

#include <windows.h>
#include <mfidl.h>
#include <mfapi.h>
#include <mferror.h>

#include "utils.h"
#include "record.h"
#include <queue>

using namespace flutter;

#define WM_RUN_DELEGATE (WM_USER + 101)

namespace record_windows {
	typedef flutter::EventSink<flutter::EncodableValue> FlEventSink;
	typedef flutter::StreamHandlerError<flutter::EncodableValue> FlStreamHandlerError;

	using FlutterRootWindowProvider = std::function<HWND()>;
	using WindowProcDelegate = std::function<std::optional<LRESULT>(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)>;
	using WindowProcDelegateRegistrator = std::function<int(WindowProcDelegate delegate)>;
	using WindowProcDelegateUnregistrator = std::function<void(int proc_id)>;

	class RecordWindowsPlugin : public flutter::Plugin {
	public:
		static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

		RecordWindowsPlugin(
			WindowProcDelegateRegistrator registrator,
			WindowProcDelegateUnregistrator unregistrator,
			FlutterRootWindowProvider window_provider
		);
		virtual ~RecordWindowsPlugin();

		// Disallow copy and assign.
		RecordWindowsPlugin(const RecordWindowsPlugin&) = delete;
		RecordWindowsPlugin& operator=(const RecordWindowsPlugin&) = delete;

		// The function to call to get the root window.
		static FlutterRootWindowProvider get_root_window;

		// A queue of callbacks to run on the main thread.
		static std::queue<std::function<void()>> callbacks;

		// Runs the given callback on the main thread.
		static void RunOnMainThread(std::function<void()> callback);

	private:
		static inline BinaryMessenger* m_binaryMessenger;

		// Called when a method is called on this plugin's channel from Dart.
		void HandleMethodCall(const MethodCall<EncodableValue>& method_call,
			std::unique_ptr<MethodResult<EncodableValue>> result);

		HRESULT CreateRecorder(std::string recorderId);
		Recorder* GetRecorder(std::string recorderId);
		HRESULT ListInputDevices(MethodResult<EncodableValue>& result);

		std::unique_ptr<RecordConfig> InitRecordConfig(const EncodableMap* args);

		std::map<std::string, std::unique_ptr<Recorder>> m_recorders{};

		// Called for top-level WindowProc delegation.
		std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

		// The registrar for this plugin, for registering top-level WindowProc delegates.
		WindowProcDelegateRegistrator m_win_proc_delegate_registrator;
		WindowProcDelegateUnregistrator m_win_proc_delegate_unregistrator;

		// The ID of the WindowProc delegate registration.
		int m_window_proc_id = -1;
	};

}  // namespace record_windows

#endif  // FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_
