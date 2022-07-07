#include "include/record_windows/record_windows_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "record_windows_plugin.h"

void RecordWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  record_windows::RecordWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
