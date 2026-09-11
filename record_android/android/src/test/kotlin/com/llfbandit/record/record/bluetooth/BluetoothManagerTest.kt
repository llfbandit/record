package com.llfbandit.record.record.bluetooth

import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.llfbandit.record.testRecordConfig
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.AudioDeviceInfoBuilder
import org.robolectric.shadows.ShadowLooper
import org.robolectric.util.ReflectionHelpers
import java.util.concurrent.TimeUnit

private const val ROLE_SOURCE = 1 // AudioPort.ROLE_SOURCE, not in the public SDK.

/** Every SCO outcome must answer `prepare()` exactly once: a stuck link is a stuck recorder. */
@RunWith(RobolectricTestRunner::class)
// Pre-31: the branch that waits for the SCO broadcast.
@Config(sdk = [30])
class BluetoothManagerTest {
  private val context: Context = ApplicationProvider.getApplicationContext()
  private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

  private lateinit var manager: BluetoothManager
  private var readyCount = 0

  @Before
  fun setUp() {
    shadowOf(audioManager).setIsBluetoothScoAvailableOffCall(true)
    manager = BluetoothManager(context, Handler(Looper.getMainLooper()))
  }

  @Test
  fun `a connected link answers once`() {
    withHeadset()
    start()
    assertEquals(0, readyCount)

    broadcast(AudioManager.SCO_AUDIO_STATE_CONNECTED)

    assertEquals(1, readyCount)
    idlePastTimeout()
    assertEquals("the timeout must not answer a second time", 1, readyCount)
  }

  @Test
  fun `a link that never connects answers after the timeout`() {
    withHeadset()
    start()
    assertEquals(0, readyCount)

    idlePastTimeout()

    assertEquals(1, readyCount)
  }

  @Test
  fun `a failed link answers without waiting for the timeout`() {
    withHeadset()
    start()

    broadcast(AudioManager.SCO_AUDIO_STATE_ERROR)

    assertEquals(1, readyCount)
    idlePastTimeout()
    assertEquals(1, readyCount)
  }

  @Test
  fun `a connect arriving after the timeout does not answer twice`() {
    withHeadset()
    start()
    idlePastTimeout()
    assertEquals(1, readyCount)

    broadcast(AudioManager.SCO_AUDIO_STATE_CONNECTED)

    assertEquals(1, readyCount)
  }

  @Test
  fun `no headset answers immediately`() {
    start()

    assertEquals(1, readyCount)
  }

  @Test
  fun `a headset answers immediately when SCO is unavailable off call`() {
    withHeadset()
    shadowOf(audioManager).setIsBluetoothScoAvailableOffCall(false)

    start()

    assertEquals(1, readyCount)
  }

  // API 31+ answers from setCommunicationDevice, with no broadcast involved.
  @Test
  @Config(sdk = [33])
  fun `a communication device answers without a broadcast`() {
    val device = scoDevice()
    shadowOf(audioManager).setInputDevices(listOf(device))
    shadowOf(audioManager).setAvailableCommunicationDevices(listOf(device))

    start()

    assertEquals(1, readyCount)
    idlePastTimeout()
    assertEquals(1, readyCount)
  }

  private fun withHeadset() {
    shadowOf(audioManager).setInputDevices(listOf(scoDevice()))
  }

  private fun scoDevice(): AudioDeviceInfo {
    val device = AudioDeviceInfoBuilder.newBuilder()
      .setType(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
      .build()

    // Left unset by the builder, so isSource() is false and filterSources() drops it.
    val port = ReflectionHelpers.getField<Any>(device, "mPort")
    ReflectionHelpers.setField(port.javaClass.superclass, port, "mRole", ROLE_SOURCE)

    return device
  }

  private fun start() {
    manager.maybeStart(testRecordConfig()) { readyCount++ }
    ShadowLooper.idleMainLooper()
  }

  private fun broadcast(state: Int) {
    context.sendBroadcast(
      Intent(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
        .putExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, state)
    )
    ShadowLooper.idleMainLooper()
  }

  private fun idlePastTimeout() = ShadowLooper.idleMainLooper(5, TimeUnit.SECONDS)
}
