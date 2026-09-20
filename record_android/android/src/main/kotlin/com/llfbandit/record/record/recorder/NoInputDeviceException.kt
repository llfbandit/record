package com.llfbandit.record.record.recorder

/** Resume found no device to replace the lost one, so the recording stays paused. */
class NoInputDeviceException(
  message: String = "No input device available to resume recording."
) : Exception(message)
