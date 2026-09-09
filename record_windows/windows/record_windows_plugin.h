#ifndef FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_


#include <flutter/plugin_registrar_windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <map>
#include <memory>

#include <windows.h>

#include "utils.h"
#include "platform_thread.h"
#include "recorder_wrapper.h"

using namespace flutter;

namespace record_windows {
	// Routes Dart calls to a recorder, one wrapper per recorderId.
	class RecordWindowsPlugin : public flutter::Plugin {
	public:
		static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

		explicit RecordWindowsPlugin(BinaryMessenger* messenger);
		virtual ~RecordWindowsPlugin();

		// Disallow copy and assign.
		RecordWindowsPlugin(const RecordWindowsPlugin&) = delete;
		RecordWindowsPlugin& operator=(const RecordWindowsPlugin&) = delete;

	private:
		BinaryMessenger* m_binaryMessenger;

		// Called when a method is called on this plugin's channel from Dart.
		void HandleMethodCall(const MethodCall<EncodableValue>& method_call,
			std::unique_ptr<MethodResult<EncodableValue>> result);

		void CreateRecorder(std::string recorderId);
		RecorderWrapper* GetRecorder(std::string recorderId);

		std::unique_ptr<RecordConfig> InitRecordConfig(const EncodableMap* args);

		// Before the recorders: their teardown still posts here.
		PlatformThread m_platform;
		std::map<std::string, std::unique_ptr<RecorderWrapper>> m_recorders{};

		// Cleared in the destructor so replies still queued on the platform thread skip.
		std::shared_ptr<bool> m_alive = std::make_shared<bool>(true);
	};

}  // namespace record_windows

#endif  // FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_
