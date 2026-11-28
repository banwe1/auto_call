package com.uglyduckling.autocall

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.provider.Settings
import android.telecom.TelecomManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

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
        private const val DIAL_STATUS_CHANNEL = "auto_call/dial_status"
        private const val PERMISSION_REQUEST_CODE = 4201

        val DIAL_PERMISSIONS = arrayOf(
            Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG
        )
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val dialStatusChannel = EventChannel(messenger, DIAL_STATUS_CHANNEL)
    private val watcher = CallStateWatcher(activity.applicationContext) { payload ->
        activity.runOnUiThread { eventSink?.success(payload) }
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    /** 手动拨号的通话跟踪（用于写入拨号记录） */
    private var manualWatcher: CallStateWatcher? = null
    private val historyHandler = Handler(Looper.getMainLooper())
    private val manualStopRunnable = Runnable {
        manualWatcher?.stop()
        manualWatcher = null
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        dialStatusChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                AutoDialService.eventSink = events
                events?.success(AutoDialService.statusMap())
            }

            override fun onCancel(arguments: Any?) {
                AutoDialService.eventSink = null
            }
        })
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
            "startAutoDial" -> startAutoDial(call, result)
            "stopAutoDial" -> {
                sendServiceAction(AutoDialService.ACTION_STOP, false)
                result.success(true)
            }
            "pauseAutoDial" -> {
                sendServiceAction(AutoDialService.ACTION_PAUSE, false)
                result.success(true)
            }
            "resumeAutoDial" -> {
                sendServiceAction(AutoDialService.ACTION_RESUME, false)
                result.success(true)
            }
            "skipNext" -> {
                sendServiceAction(AutoDialService.ACTION_SKIP_NEXT, false)
                result.success(true)
            }
            "redial" -> {
                sendServiceAction(AutoDialService.ACTION_REDIAL, false)
                result.success(true)
            }
            "removeNext" -> {
                sendServiceAction(AutoDialService.ACTION_REMOVE_NEXT, false)
                result.success(true)
            }
            "getAutoDialStatus" -> result.success(AutoDialService.statusMap())
            "getDialSettings" -> result.success(DialPrefs.readAll(activity))
            "setDialSettings" -> setDialSettings(call, result)
            "getDialStats" -> result.success(DialStats.snapshot(activity))
            "clearDialStats" -> {
                DialStats.clearExceptToday(activity)
                result.success(DialStats.snapshot(activity))
            }
            "recordNewCustomer" -> {
                // 号码被标记为「客户」时累加当日新客户数
                DialStats.addNewCustomer(activity, call.argument<Int>("count") ?: 1)
                result.success(true)
            }
            "getDialHistory" -> result.success(DialHistory.snapshot(activity))
            "filterInCallLog" -> filterInCallLog(call, result)
            "clearDialHistory" -> {
                DialHistory.clear(activity)
                result.success(DialHistory.snapshot(activity))
            }
            "setDialHistoryLimit" -> {
                DialHistory.setLimit(
                    activity,
                    call.argument<Int>("limit") ?: DialHistory.DEFAULT_LIMIT
                )
                result.success(DialHistory.snapshot(activity))
            }
            "hangup" -> result.success(AutoDialAccessibilityService.requestHangup())
            "isAccessibilityEnabled" -> result.success(isAccessibilityEnabled())
            "isAccessibilityConnected" ->
                result.success(AutoDialAccessibilityService.isConnected())
            "openAccessibilitySettings" -> openAccessibilitySettings(result)
            else -> result.notImplemented()
        }
    }

    private fun isAccessibilityEnabled(): Boolean {
        val expected = ComponentName(
            activity,
            AutoDialAccessibilityService::class.java
        ).flattenToString()
        val enabled = try {
            Settings.Secure.getString(
                activity.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
        } catch (e: Exception) {
            null
        } ?: return false
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    private fun openAccessibilitySettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("open_failed", e.message ?: e.toString(), null)
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
        if (subscriptionId != null && subscriptionId >= 0) {
            try {
                val telecom =
                    activity.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                val extras = Bundle()
                SimHelper.phoneAccountFor(activity, subscriptionId)?.let { handle ->
                    extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle)
                }
                telecom.placeCall(Uri.fromParts("tel", number, null), extras)
                DialStats.recordCall(activity, false, 0, 0)
                trackManualCall(number)
                result.success(mapOf("ok" to true, "simIndex" to -1))
            } catch (e: Exception) {
                result.error("dial_failed", e.message ?: e.toString(), null)
            }
            return
        }

        // 未指定卡：按保存的模式（跟随系统 / 卡1 / 卡2 / 双卡交替，含前缀）
        val pair = SimHelper.placeCall(activity, number, DialPrefs.getMode(activity))
        if (pair.first) {
            DialStats.recordCall(activity, false, 0, 0)
            trackManualCall(number)
            result.success(mapOf("ok" to true, "simIndex" to pair.second))
        } else {
            result.error("dial_failed", "拨号失败", null)
        }
    }

    /**
     * 手动拨号：跟踪本次通话，挂断后写入拨号记录（含接通状态与通话时长）。
     * 10 分钟兜底停止，避免用户取消拨号后监听常驻。
     */
    private fun trackManualCall(number: String) {
        historyHandler.removeCallbacks(manualStopRunnable)
        manualWatcher?.stop()
        manualWatcher = null

        var sawActive = false
        var watcherRef: CallStateWatcher? = null

        val watcher = CallStateWatcher(activity.applicationContext) { payload ->
            when (payload["state"] as? String) {
                "offhook", "ringing" -> sawActive = true
                "idle" -> {
                    val wasActive = sawActive
                    sawActive = false
                    if (wasActive) {
                        val connected = payload["connected"] as? Boolean ?: false
                        val duration = (payload["durationSec"] as? Number)?.toInt() ?: 0
                        DialHistory.add(
                            activity,
                            DialHistory.Entry(
                                number = number,
                                connected = connected,
                                talkSec = duration,
                                dialSec = 0,
                                at = System.currentTimeMillis(),
                                source = DialHistory.SOURCE_MANUAL
                            )
                        )
                        watcherRef?.stop()
                        manualWatcher = null
                        historyHandler.removeCallbacks(manualStopRunnable)
                    }
                }
            }
        }
        watcherRef = watcher
        manualWatcher = watcher
        watcher.start()
        historyHandler.postDelayed(manualStopRunnable, 10 * 60 * 1000L)
    }

    private fun startAutoDial(call: MethodCall, result: MethodChannel.Result) {
        val queue = call.argument<List<String>>("queue") ?: emptyList()
        if (queue.isEmpty()) {
            result.error("empty_queue", "没有可拨打的号码", null)
            return
        }
        try {
            val payload = JSONArray(queue).toString()
            val intent = Intent(activity, AutoDialService::class.java)
                .setAction(AutoDialService.ACTION_START)
                .putExtra(AutoDialService.EXTRA_QUEUE, payload)
            sendServiceAction(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("start_failed", e.message ?: e.toString(), null)
        }
    }

    private fun sendServiceAction(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
    }

    private fun sendServiceAction(action: String, foreground: Boolean) {
        val intent = Intent(activity, AutoDialService::class.java).setAction(action)
        if (foreground && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
    }

    /** 传入号码里，哪些在系统通话记录中出现过（导入「通话记录去重」用） */
    private fun filterInCallLog(call: MethodCall, result: MethodChannel.Result) {
        val numbers = call.argument<List<String>>("numbers") ?: emptyList()
        if (numbers.isEmpty()) {
            result.success(emptyList<String>())
            return
        }
        if (!SimHelper.hasPermission(activity, Manifest.permission.READ_CALL_LOG)) {
            result.success(emptyList<String>())
            return
        }
        try {
            val logged = mutableSetOf<String>()
            activity.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER),
                null,
                null,
                "${CallLog.Calls.DATE} DESC"
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val raw = cursor.getString(0) ?: continue
                    val digits = raw.filter { it.isDigit() }
                    if (digits.length >= 7) {
                        logged.add(digits.takeLast(11))
                    }
                }
            }
            val kept = numbers.filter { number ->
                val digits = number.filter { it.isDigit() }
                digits.length >= 7 && logged.contains(digits.takeLast(11))
            }
            result.success(kept)
        } catch (e: Exception) {
            result.error("query_failed", e.message ?: e.toString(), null)
        }
    }

    private fun setDialSettings(call: MethodCall, result: MethodChannel.Result) {
        val ctx = activity.applicationContext
        call.argument<Int>("mode")?.let { DialPrefs.setMode(ctx, it) }
        call.argument<Boolean>("compatMode")?.let { DialPrefs.setCompatMode(ctx, it) }
        call.argument<Int>("intervalSec")?.let { DialPrefs.setIntervalSec(ctx, it) }
        call.argument<Boolean>("autoNext")?.let { DialPrefs.setAutoNext(ctx, it) }
        call.argument<Boolean>("returnToApp")?.let { DialPrefs.setReturnToApp(ctx, it) }
        call.argument<Int>("remindEvery")?.let { DialPrefs.setRemindEvery(ctx, it) }
        call.argument<List<String>>("prefix1")?.let { DialPrefs.setPrefixes(ctx, 1, it) }
        call.argument<List<String>>("prefix2")?.let { DialPrefs.setPrefixes(ctx, 2, it) }
        result.success(DialPrefs.readAll(ctx))
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
