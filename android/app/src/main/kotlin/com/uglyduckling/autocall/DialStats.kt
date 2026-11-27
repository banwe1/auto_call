package com.uglyduckling.autocall

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 每日拨号统计：全部在原生侧累加，App 被杀/后台都不会漏记。
 * 存储结构：{"2026-11-27":{"total":12,"connected":6,"newCustomer":0,"talkSec":139,"dialSec":394}}
 */
object DialStats {

    private const val NAME = "dial_stats"
    private const val KEY = "days"

    data class Day(
        var total: Int = 0,
        var connected: Int = 0,
        var newCustomer: Int = 0,
        var talkSec: Int = 0,
        var dialSec: Int = 0
    )

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    private fun dayKey(offsetMonths: Int = 0): String {
        val cal = Calendar.getInstance()
        cal.time = Date()
        cal.add(Calendar.MONTH, offsetMonths)
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(cal.time)
    }

    @Synchronized
    fun readAll(context: Context): MutableMap<String, Day> {
        val raw = prefs(context).getString(KEY, null) ?: return mutableMapOf()
        val result = mutableMapOf<String, Day>()
        try {
            val json = JSONObject(raw)
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val o = json.optJSONObject(key) ?: continue
                result[key] = Day(
                    total = o.optInt("total"),
                    connected = o.optInt("connected"),
                    newCustomer = o.optInt("newCustomer"),
                    talkSec = o.optInt("talkSec"),
                    dialSec = o.optInt("dialSec")
                )
            }
        } catch (e: Exception) {
            // 数据损坏时按空处理
        }
        return result
    }

    @Synchronized
    private fun saveAll(context: Context, days: Map<String, Day>) {
        val json = JSONObject()
        for ((key, value) in days) {
            json.put(
                key,
                JSONObject().apply {
                    put("total", value.total)
                    put("connected", value.connected)
                    put("newCustomer", value.newCustomer)
                    put("talkSec", value.talkSec)
                    put("dialSec", value.dialSec)
                }
            )
        }
        prefs(context).edit().putString(KEY, json.toString()).apply()
    }

    /** 每通电话结束调用：total+1、接通时 connected+1、累加通话/拨号时长 */
    @Synchronized
    fun recordCall(context: Context, connected: Boolean, talkSec: Int, dialSec: Int) {
        val days = readAll(context)
        val day = days.getOrPut(dayKey()) { Day() }
        day.total += 1
        if (connected) day.connected += 1
        day.talkSec += talkSec.coerceAtLeast(0)
        day.dialSec += dialSec.coerceAtLeast(0)
        saveAll(context, days)
    }

    /** 号码被标记为「客户」时调用 */
    @Synchronized
    fun addNewCustomer(context: Context, count: Int = 1) {
        val days = readAll(context)
        val day = days.getOrPut(dayKey()) { Day() }
        day.newCustomer += count
        saveAll(context, days)
    }

    /** 清空（保留今天，与 base 的"今日报表禁止删除"一致） */
    @Synchronized
    fun clearExceptToday(context: Context) {
        val days = readAll(context)
        val todayKey = dayKey()
        val today = days[todayKey] ?: Day()
        saveAll(context, mapOf(todayKey to today))
    }

    private fun toMap(date: String, day: Day): Map<String, Any?> = mapOf(
        "date" to date,
        "total" to day.total,
        "connected" to day.connected,
        "newCustomer" to day.newCustomer,
        "talkSec" to day.talkSec,
        "dialSec" to day.dialSec
    )

    private fun aggregate(days: Map<String, Day>, monthKey: String, label: String): Map<String, Any?> {
        var total = 0
        var connected = 0
        var newCustomer = 0
        var talkSec = 0
        var dialSec = 0
        for ((key, value) in days) {
            if (key.startsWith(monthKey)) {
                total += value.total
                connected += value.connected
                newCustomer += value.newCustomer
                talkSec += value.talkSec
                dialSec += value.dialSec
            }
        }
        return toMap(label, Day(total, connected, newCustomer, talkSec, dialSec))
    }

    /** 给 Flutter 的完整快照 */
    fun snapshot(context: Context): Map<String, Any?> {
        val days = readAll(context)
        val todayKey = dayKey()
        val today = days[todayKey] ?: Day()
        val monthKey = todayKey.substring(0, 7)
        val lastMonthKey = dayKey(offsetMonths = -1).substring(0, 7)

        val list = days.entries
            .sortedByDescending { it.key }
            .map { toMap(it.key, it.value) }

        return mapOf(
            "today" to toMap(todayKey, today),
            "days" to list,
            "month" to aggregate(days, monthKey, "本月"),
            "lastMonth" to aggregate(days, lastMonthKey, "上月")
        )
    }
}
