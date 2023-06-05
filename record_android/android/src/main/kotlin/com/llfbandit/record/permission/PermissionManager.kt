package com.llfbandit.record.permission

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener

class PermissionManager : RequestPermissionsResultListener {
    private var resultCallback: PermissionResultCallback? = null
    private var activity: Activity? = null
    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == RECORD_AUDIO_REQUEST_CODE && resultCallback != null) {
            val granted =
                grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            resultCallback!!.onResult(granted)
            resultCallback = null
            return true
        }
        return false
    }

    fun hasPermission(resultCallback: PermissionResultCallback) {
        if (activity == null) {
            resultCallback.onResult(false)
            return
        }
        if (!isPermissionGranted(activity!!)) {
            this.resultCallback = resultCallback
            ActivityCompat.requestPermissions(
                activity!!, arrayOf(Manifest.permission.RECORD_AUDIO),
                RECORD_AUDIO_REQUEST_CODE
            )
        } else {
            resultCallback.onResult(true)
        }
    }

    private fun isPermissionGranted(activity: Activity): Boolean {
        val result = ActivityCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
        return result == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        private const val RECORD_AUDIO_REQUEST_CODE = 1001
    }
}