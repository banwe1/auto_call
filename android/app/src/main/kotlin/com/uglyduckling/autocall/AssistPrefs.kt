package com.uglyduckling.autocall

import android.content.Context
import android.content.SharedPreferences

/**
 * 辅助功能设置（与 Flutter 通过 MethodChannel 同步）
 *
 * 默认值对齐 base 的「默认项」截图：
 * 自动扬声器=开、自动录音=关、未接通自动挂断=开（40 秒）、已接通自动挂断=关（60 秒）
 */
object AssistPrefs {

    private const val NAME = "assist_settings"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun isAutoSpeaker(context: Context): Boolean =
        prefs(context).getBoolean("auto_speaker", true)

    fun setAutoSpeaker(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("auto_speaker", value).apply()
    }

    fun isAutoRecord(context: Context): Boolean =
        prefs(context).getBoolean("auto_record", false)

    fun setAutoRecord(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("auto_record", value).apply()
    }

    fun isHangupUnanswered(context: Context): Boolean =
        prefs(context).getBoolean("hangup_unanswered", true)

    fun setHangupUnanswered(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("hangup_unanswered", value).apply()
    }

    fun getUnansweredSec(context: Context): Int =
        prefs(context).getInt("unanswered_sec", 40).coerceIn(1, 600)

    fun setUnansweredSec(context: Context, value: Int) {
        prefs(context).edit().putInt("unanswered_sec", value.coerceIn(1, 600)).apply()
    }

    fun isHangupAnswered(context: Context): Boolean =
        prefs(context).getBoolean("hangup_answered", false)

    fun setHangupAnswered(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("hangup_answered", value).apply()
    }

    fun getAnsweredSec(context: Context): Int =
        prefs(context).getInt("answered_sec", 60).coerceIn(1, 3600)

    fun setAnsweredSec(context: Context, value: Int) {
        prefs(context).edit().putInt("answered_sec", value.coerceIn(1, 3600)).apply()
    }

    /** 通话状态同步（仅保存，功能未实现） */
    fun isCallStateSync(context: Context): Boolean =
        prefs(context).getBoolean("call_state_sync", false)

    fun setCallStateSync(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("call_state_sync", value).apply()
    }

    fun readAll(context: Context): Map<String, Any?> = mapOf(
        "autoSpeaker" to isAutoSpeaker(context),
        "autoRecord" to isAutoRecord(context),
        "hangupUnanswered" to isHangupUnanswered(context),
        "unansweredSec" to getUnansweredSec(context),
        "hangupAnswered" to isHangupAnswered(context),
        "answeredSec" to getAnsweredSec(context),
        "callStateSync" to isCallStateSync(context)
    )
}
