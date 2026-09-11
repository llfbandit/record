package com.llfbandit.record.record.audio_manager

import android.content.Context
import android.os.Handler
import com.llfbandit.record.record.bluetooth.BluetoothManager
import com.llfbandit.record.record.model.RecordConfig

/** [AudioEnvironment] backed by the platform `AudioManager`. */
class AndroidAudioEnvironment(
  context: Context,
  handler: Handler,
) : AudioEnvironment {
  override var onEvent: (EnvironmentEvent) -> Unit = {}

  private val session = AudioSessionManager(
    context,
    handler,
    onFocusLoss = { onEvent(EnvironmentEvent.FocusLost) },
    onFocusGain = { onEvent(EnvironmentEvent.FocusRegained) },
  )
  private val bluetooth = BluetoothManager(context, handler)

  override fun prepare(config: RecordConfig, onReady: () -> Unit) {
    session.save()
    bluetooth.maybeStart(config) { onReady() }
  }

  override fun activate(config: RecordConfig) = session.apply(config)

  override fun release(config: RecordConfig) = session.restore(config)

  override fun dispose() = bluetooth.stop()
}
