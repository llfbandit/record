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

using namespace flutter;

namespace record_windows {
	typedef flutter::EventSink<flutter::EncodableValue> FlEventSink;
	typedef flutter::StreamHandlerError<flutter::EncodableValue> FlStreamHandlerError;

	class RecordWindowsPlugin : public flutter::Plugin {
	public:
		static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

		RecordWindowsPlugin();
		virtual ~RecordWindowsPlugin();

		// Disallow copy and assign.
		RecordWindowsPlugin(const RecordWindowsPlugin&) = delete;
		RecordWindowsPlugin& operator=(const RecordWindowsPlugin&) = delete;

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
	};

}  // namespace record_windows

#endif  // FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_
