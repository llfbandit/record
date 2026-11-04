package com.llfbandit.record.permission

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener

class PermissionManager(private val context: Context) : RequestPermissionsResultListener {
  private val pending = mutableListOf<PermissionResultCallback>()
  private var activity: Activity? = null

  fun setActivity(activity: Activity?) {
    this.activity = activity
  }

  fun answerPending() = answerAll(isPermissionGranted())

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<String>,
    grantResults: IntArray
  ): Boolean {
    if (requestCode != RECORD_AUDIO_REQUEST_CODE || pending.isEmpty()) return false
    val index = permissions.indexOf(Manifest.permission.RECORD_AUDIO)
    // Another request sharing our code; an interrupted one comes back empty and is ours.
    if (index < 0 && permissions.isNotEmpty()) return false

    answerAll(index >= 0 && grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED)
    return true
  }

  private fun answerAll(granted: Boolean) {
    val waiting = pending.toList()
    pending.clear()
    waiting.forEach { it.onResult(granted) }
  }

  fun hasPermission(request: Boolean = true, resultCallback: PermissionResultCallback) {
    val isGranted = isPermissionGranted()
    val activity = activity
    if (isGranted || !request || activity == null) {
      resultCallback.onResult(isGranted)
      return
    }

    pending += resultCallback
    if (pending.size == 1) {
      ActivityCompat.requestPermissions(
        activity, arrayOf(Manifest.permission.RECORD_AUDIO), RECORD_AUDIO_REQUEST_CODE
      )
    }
  }

  private fun isPermissionGranted(): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
      PackageManager.PERMISSION_GRANTED

  companion object {
    internal const val RECORD_AUDIO_REQUEST_CODE = 1001
  }
}
