package com.uglyduckling.autocall

import android.content.Context
import android.content.SharedPreferences

/**
 * 拨号相关设置的本地存储（与 Flutter 通过 MethodChannel 同步）。
 */
object DialPrefs {

    private const val NAME = "dial_settings"

    const val MODE_FOLLOW = 0      // 跟随系统
    const val MODE_SIM1 = 1        // 卡1
    const val MODE_SIM2 = 2        // 卡2
    const val MODE_ALTERNATE = 3   // 双卡交替

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun getMode(context: Context): Int =
        prefs(context).getInt("dial_mode", MODE_FOLLOW)

    fun setMode(context: Context, mode: Int) {
        prefs(context).edit().putInt("dial_mode", mode).apply()
    }

    fun getAltIndex(context: Context): Int = prefs(context).getInt("alt_index", 0)

    fun setAltIndex(context: Context, index: Int) {
        prefs(context).edit().putInt("alt_index", index).apply()
    }

    /** 某张卡的前缀列表（用 | 分隔存储） */
    fun getPrefixes(context: Context, sim: Int): List<String> {
        val raw = prefs(context).getString("prefix_$sim", "").orEmpty()
        return raw.split('|').map { it.trim() }.filter { it.isNotEmpty() }
    }

    fun setPrefixes(context: Context, sim: Int, values: List<String>) {
        prefs(context)
            .edit()
            .putString("prefix_$sim", values.filter { it.isNotBlank() }.joinToString("|"))
            .apply()
    }

    /** 依次轮换取下一个前缀 */
    fun nextPrefix(context: Context, sim: Int): String {
        val list = getPrefixes(context, sim)
        if (list.isEmpty()) return ""
        val key = "prefix_index_$sim"
        var index = prefs(context).getInt(key, 0)
        if (index < 0 || index >= list.size) index = 0
        val value = list[index]
        prefs(context).edit().putInt(key, (index + 1) % list.size).apply()
        return value
    }

    fun isCompatMode(context: Context): Boolean =
        prefs(context).getBoolean("compat_mode", false)

    fun setCompatMode(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("compat_mode", value).apply()
    }

    fun getIntervalSec(context: Context): Int =
        prefs(context).getInt("interval_sec", 5)

    fun setIntervalSec(context: Context, value: Int) {
        prefs(context).edit().putInt("interval_sec", value).apply()
    }

    fun isAutoNext(context: Context): Boolean =
        prefs(context).getBoolean("auto_next", true)

    fun setAutoNext(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("auto_next", value).apply()
    }

    fun isReturnToApp(context: Context): Boolean =
        prefs(context).getBoolean("return_to_app", true)

    fun setReturnToApp(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("return_to_app", value).apply()
    }

    /** 全部设置，供 Flutter 读取 */
    fun readAll(context: Context): Map<String, Any?> = mapOf(
        "mode" to getMode(context),
        "prefix1" to getPrefixes(context, 1),
        "prefix2" to getPrefixes(context, 2),
        "intervalSec" to getIntervalSec(context),
        "compatMode" to isCompatMode(context),
        "autoNext" to isAutoNext(context),
        "returnToApp" to isReturnToApp(context)
    )
}
