package com.llfbandit.record

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
      pm.setActivity(binding.activity)
      activityBinding?.addRequestPermissionsResultListener(pm)
    }
  }

  // The recreated activity delivers the pending dialog's result.
  override fun onDetachedFromActivityForConfigChanges() {
    detachActivity()
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    detachActivity()
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivity() {
    detachActivity()
    // No activity comes back to deliver the dialog's result.
    permissionManager?.answerPending()
  }

  private fun detachActivity() {
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
    permissionManager = PermissionManager(binding.applicationContext)
    callHandler = MethodCallHandlerImpl(
      permissionManager!!,
      binding.binaryMessenger,
      binding.applicationContext
    )
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