#include "record_windows_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace record_windows {

// static
void RecordWindowsPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<RecordWindowsPlugin>();
  registrar->AddPlugin(std::move(plugin));
}

RecordWindowsPlugin::RecordWindowsPlugin() {}

RecordWindowsPlugin::~RecordWindowsPlugin() {}

}  // namespace record_windows
