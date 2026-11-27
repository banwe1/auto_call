package com.uglyduckling.autocall

import android.Manifest
import android.content.Context
import android.os.Build
import android.provider.CallLog
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager

/**
 * 通话状态监听：上报 idle / ringing / offhook，
 * 并在挂断（idle）时查询 CallLog 判断是否接通、通话时长。
 */
class CallStateWatcher(
    private val context: Context,
    private val onEvent: (Map<String, Any?>) -> Unit
) {

    private val telephonyManager: TelephonyManager? =
        context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager

    private var telephonyCallback: TelephonyCallback? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var started = false

    fun start() {
        val tm = telephonyManager ?: return
        if (started) return
        started = true

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    handleState(state)
                }
            }
            telephonyCallback = callback
            tm.registerTelephonyCallback(context.mainExecutor, callback)
        } else {
            @Suppress("DEPRECATION")
            val listener = object : PhoneStateListener() {
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    handleState(state)
                }
            }
            phoneStateListener = listener
            @Suppress("DEPRECATION")
            tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    @Suppress("DEPRECATION")
    fun stop() {
        val tm = telephonyManager ?: return
        if (!started) return
        started = false
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyCallback?.let { tm.unregisterTelephonyCallback(it) }
            } else {
                phoneStateListener?.let { tm.listen(it, PhoneStateListener.LISTEN_NONE) }
            }
        } catch (e: Exception) {
            // ignore
        }
        telephonyCallback = null
        phoneStateListener = null
    }

    private fun handleState(state: Int) {
        val name = when (state) {
            TelephonyManager.CALL_STATE_RINGING -> "ringing"
            TelephonyManager.CALL_STATE_OFFHOOK -> "offhook"
            else -> "idle"
        }
        val payload = mutableMapOf<String, Any?>("state" to name)
        if (name == "idle") {
            lastOutgoingCall()?.let { payload.putAll(it) }
        }
        onEvent(payload)
    }

    /** 查最近 5 分钟内的最后一通外呼记录 */
    private fun lastOutgoingCall(): Map<String, Any?>? {
        if (!SimHelper.hasPermission(context, Manifest.permission.READ_CALL_LOG)) return null
        return try {
            val cursor = context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls.NUMBER,
                    CallLog.Calls.DURATION,
                    CallLog.Calls.TYPE,
                    CallLog.Calls.DATE
                ),
                null,
                null,
                CallLog.Calls.DATE + " DESC"
            )
            cursor?.use { c ->
                if (c.moveToFirst()) {
                    val number = c.getString(0) ?: ""
                    val duration = c.getLong(1)
                    val type = c.getInt(2)
                    val date = c.getLong(3)
                    val recent = System.currentTimeMillis() - date <= 5 * 60 * 1000L
                    if (recent) {
                        return mapOf(
                            "number" to number,
                            "durationSec" to duration,
                            "callType" to type,
                            "connected" to (type == CallLog.Calls.OUTGOING_TYPE && duration > 0)
                        )
                    }
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }
}
