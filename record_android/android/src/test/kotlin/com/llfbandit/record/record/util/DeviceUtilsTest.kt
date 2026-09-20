package com.llfbandit.record.record.util

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import androidx.test.core.app.ApplicationProvider
import com.llfbandit.record.testAudioDevice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Checks how DeviceUtils finds a device again after a re-plug. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DeviceUtilsTest {
  private val context: Context = ApplicationProvider.getApplicationContext()
  private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

  private val buds = testAudioDevice(id = 7, AudioDeviceInfo.TYPE_BLUETOOTH_SCO, "24:29:34:AB:85:F1")

  @Test
  fun `finds a device still plugged in`() {
    plugIn(buds)
    assertEquals(7, find(buds)?.id)
  }

  @Test
  fun `finds a re-plugged device under its new id`() {
    plugIn(testAudioDevice(id = 12, AudioDeviceInfo.TYPE_BLUETOOTH_SCO, "24:29:34:AB:85:F1"))
    assertEquals(12, find(buds)?.id)
  }

  @Test
  fun `does not take another device of the same type`() {
    plugIn(testAudioDevice(id = 12, AudioDeviceInfo.TYPE_BLUETOOTH_SCO, "60:38:0E:B8:70:02"))
    assertNull(find(buds))
  }

  @Test
  fun `does not match on an empty address`() {
    plugIn(testAudioDevice(id = 12, AudioDeviceInfo.TYPE_USB_DEVICE))
    assertNull(find(testAudioDevice(id = 7, AudioDeviceInfo.TYPE_USB_DEVICE)))
  }

  private fun plugIn(vararg devices: AudioDeviceInfo) =
    shadowOf(audioManager).setInputDevices(devices.toList())

  private fun find(device: AudioDeviceInfo) = DeviceUtils.findInputDevice(context, device)
}
