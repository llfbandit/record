package com.llfbandit.record

import com.llfbandit.record.methodcall.MethodCallHandlerImpl
import com.llfbandit.record.permission.PermissionManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

/**
 * RecordPlugin
 */
class RecordPlugin : FlutterPlugin, ActivityAware {
    /// The MethodChannel that will the communication between Flutter and native Android
    private var methodChannel: MethodChannel? = null

    /// Our call handler
    private var callHandler: MethodCallHandlerImpl? = null
    private var permissionManager: PermissionManager? = null
    private var activityBinding: ActivityPluginBinding? = null

    /////////////////////////////////////////////////////////////////////////////
    /// FlutterPlugin
    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        startPlugin(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        stopPlugin()
    }
    /// END FlutterPlugin
    /////////////////////////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////////////////////////
    /// ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding

        val pm = permissionManager
        if (pm != null) {
            permissionManager?.setActivity(binding.activity)
            activityBinding?.addRequestPermissionsResultListener(pm)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onDetachedFromActivity()
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        val pm = permissionManager
        if (pm != null) {
            pm.setActivity(null)
            activityBinding?.removeRequestPermissionsResultListener(pm)
        }

        activityBinding = null
    }
    /// END ActivityAware
    /////////////////////////////////////////////////////////////////////////////

    private fun startPlugin(binding: FlutterPluginBinding) {
        permissionManager = PermissionManager()
        callHandler = MethodCallHandlerImpl(permissionManager!!, binding.binaryMessenger, binding.applicationContext)
        methodChannel = MethodChannel(binding.binaryMessenger, MESSAGES_CHANNEL)
        methodChannel?.setMethodCallHandler(callHandler)
    }

    private fun stopPlugin() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        callHandler?.dispose()
        callHandler = null
    }

    companion object {
        const val MESSAGES_CHANNEL = "com.llfbandit.record/messages"
    }
}