package com.llfbandit.record

import android.media.AudioDeviceInfo
import org.robolectric.shadows.AudioDeviceInfoBuilder
import org.robolectric.util.ReflectionHelpers

private const val ROLE_SOURCE = 1 // AudioPort.ROLE_SOURCE, not in the public SDK.

/** Builds an input [AudioDeviceInfo] with the id and address the Robolectric builder can't set. Needs Robolectric. */
fun testAudioDevice(
  id: Int,
  type: Int = AudioDeviceInfo.TYPE_USB_DEVICE,
  address: String = "",
): AudioDeviceInfo {
  val device = AudioDeviceInfoBuilder.newBuilder().setType(type).build()
  val port = ReflectionHelpers.getField<Any>(device, "mPort")
  val audioPort = port.javaClass.superclass

  // The builder leaves mRole unset, so isSource() is false and filterSources() drops the device.
  ReflectionHelpers.setField(audioPort, port, "mRole", ROLE_SOURCE)
  ReflectionHelpers.setField(ReflectionHelpers.getField<Any>(port, "mHandle"), "mId", id)
  ReflectionHelpers.setField(port.javaClass, port, "mAddress", address)
  return device
}
