#pragma once

#include <windows.h>
#include <flutter/encodable_value.h>
#include <string>

#include "record_config.h"

namespace record_windows {
namespace AudioDevice {

HRESULT ListInputDevices(flutter::EncodableList& devices);
HRESULT IsEncoderSupported(const std::string& encoderName, bool* supported);
// Returns the id an empty deviceId stands for.
HRESULT GetDefaultInputDeviceId(std::string& deviceId);
// Needs a real deviceId, because IMMDeviceEnumerator::GetDevice can't resolve an empty one.
HRESULT AdjustConfigToDeviceCaps(RecordConfig& config, const std::string& deviceId);
HRESULT AdjustConfigToCodecCaps(RecordConfig& config);
void    WarmCodecCapsAsync();

} // namespace AudioDevice
} // namespace record_windows
