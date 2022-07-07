#ifndef FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace record_windows {

class RecordWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  RecordWindowsPlugin();

  virtual ~RecordWindowsPlugin();

  // Disallow copy and assign.
  RecordWindowsPlugin(const RecordWindowsPlugin&) = delete;
  RecordWindowsPlugin& operator=(const RecordWindowsPlugin&) = delete;
};

}  // namespace record_windows

#endif  // FLUTTER_PLUGIN_RECORD_WINDOWS_PLUGIN_H_
