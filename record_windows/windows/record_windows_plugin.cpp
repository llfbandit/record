#include "include/record_windows/record_windows_plugin.h"
#include "record_windows.h"

void RecordWindowsPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  record::RecordWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
