package com.uglyduckling.autocall

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.telecom.TelecomManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 与 Flutter 通信：SIM 列表、拨号（指定卡）、权限、通话状态事件。
 */
class DialBridge(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "auto_call/dial"
        private const val EVENT_CHANNEL = "auto_call/call_state"
        private const val PERMISSION_REQUEST_CODE = 4201

        val DIAL_PERMISSIONS = arrayOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG
        )
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val watcher = CallStateWatcher(activity.applicationContext) { payload ->
        activity.runOnUiThread { eventSink?.success(payload) }
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermissions" -> result.success(hasAllPermissions())
            "requestPermissions" -> requestPermissions(result)
            "listSims" -> result.success(
                mapOf(
                    "granted" to SimHelper.hasPermission(activity, Manifest.permission.READ_PHONE_STATE),
                    "sims" to SimHelper.listSims(activity)
                )
            )
            "dial" -> dial(call, result)
            else -> result.notImplemented()
        }
    }

    private fun hasAllPermissions(): Boolean =
        DIAL_PERMISSIONS.all { SimHelper.hasPermission(activity, it) }

    private fun requestPermissions(result: MethodChannel.Result) {
        val missing = DIAL_PERMISSIONS.filter {
            !SimHelper.hasPermission(activity, it)
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pending.success(granted)
    }

    private fun dial(call: MethodCall, result: MethodChannel.Result) {
        val number = call.argument<String>("number")?.trim()
        if (number.isNullOrEmpty()) {
            result.error("bad_args", "号码为空", null)
            return
        }
        if (!SimHelper.hasPermission(activity, Manifest.permission.CALL_PHONE)) {
            result.error("permission", "缺少拨打电话权限", null)
            return
        }

        val subscriptionId = call.argument<Int>("subscriptionId")
        try {
            val telecom = activity.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val uri = Uri.fromParts("tel", number, null)
            val extras = Bundle()

            if (subscriptionId != null && subscriptionId >= 0) {
                SimHelper.phoneAccountFor(activity, subscriptionId)?.let { handle ->
                    extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                }
            }

            telecom.placeCall(uri, extras)
            result.success(mapOf("ok" to true))
        } catch (e: Exception) {
            result.error("dial_failed", e.message ?: e.toString(), null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        watcher.start()
    }

    override fun onCancel(arguments: Any?) {
        watcher.stop()
        eventSink = null
    }
}
