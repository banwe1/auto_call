package com.uglyduckling.autocall

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 拨号记录：每通电话结束写入一条，默认保留 100 条。
 *
 * - 保留条数可由用户修改（`limit`），写入时自动截断最旧的记录；
 * - 存储于 SharedPreferences("dial_history")，`entries` 为 JSON 数组，最新在前；
 * - 全部操作在原生侧完成，App 被杀或后台都不会漏记。
 */
object DialHistory {

    private const val NAME = "dial_history"
    private const val KEY_ENTRIES = "entries"
    private const val KEY_LIMIT = "limit"

    /** 默认保留条数（与 base 一致） */
    const val DEFAULT_LIMIT = 100

    private const val MAX_LIMIT = 5000

    /** 自动连拨 */
    const val SOURCE_AUTO = "auto"

    /** 手动拨号 */
    const val SOURCE_MANUAL = "manual"

    data class Entry(
        val number: String,
        val connected: Boolean,
        val talkSec: Int,
        val dialSec: Int,
        val at: Long,
        val batchId: String = "",
        val batchName: String = "",
        val source: String = SOURCE_AUTO
    )

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun limit(context: Context): Int =
        prefs(context).getInt(KEY_LIMIT, DEFAULT_LIMIT).coerceIn(1, MAX_LIMIT)

    fun setLimit(context: Context, value: Int) {
        prefs(context)
            .edit()
            .putInt(KEY_LIMIT, value.coerceIn(1, MAX_LIMIT))
            .apply()
    }

    @Synchronized
    fun readAll(context: Context): List<Entry> {
        val raw = prefs(context).getString(KEY_ENTRIES, null) ?: return emptyList()
        val result = mutableListOf<Entry>()
        try {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val o = array.optJSONObject(i) ?: continue
                val number = o.optString("number")
                if (number.isEmpty()) continue
                result.add(
                    Entry(
                        number = number,
                        connected = o.optBoolean("connected"),
                        talkSec = o.optInt("talkSec"),
                        dialSec = o.optInt("dialSec"),
                        at = o.optLong("at"),
                        batchId = o.optString("batchId"),
                        batchName = o.optString("batchName"),
                        source = o.optString("source", SOURCE_AUTO)
                    )
                )
            }
        } catch (e: Exception) {
            // 数据损坏时按空处理
        }
        return result
    }

    @Synchronized
    private fun saveAll(context: Context, entries: List<Entry>) {
        val array = JSONArray()
        for (e in entries) {
            array.put(
                JSONObject().apply {
                    put("number", e.number)
                    put("connected", e.connected)
                    put("talkSec", e.talkSec)
                    put("dialSec", e.dialSec)
                    put("at", e.at)
                    put("batchId", e.batchId)
                    put("batchName", e.batchName)
                    put("source", e.source)
                }
            )
        }
        prefs(context).edit().putString(KEY_ENTRIES, array.toString()).apply()
    }

    /** 追加一条记录（超出保留条数时丢弃最旧的） */
    @Synchronized
    fun add(context: Context, entry: Entry) {
        if (entry.number.isEmpty()) return
        val list = ArrayList(readAll(context))
        list.add(0, entry)
        val max = limit(context)
        while (list.size > max) {
            list.removeAt(list.size - 1)
        }
        saveAll(context, list)
    }

    @Synchronized
    fun clear(context: Context) {
        saveAll(context, emptyList())
    }

    private fun toMap(e: Entry): Map<String, Any?> = mapOf(
        "number" to e.number,
        "connected" to e.connected,
        "talkSec" to e.talkSec,
        "dialSec" to e.dialSec,
        "at" to e.at,
        "time" to SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(e.at)),
        "batchId" to e.batchId,
        "batchName" to e.batchName,
        "source" to e.source
    )

    /** 给 Flutter 的快照 */
    fun snapshot(context: Context): Map<String, Any?> {
        val entries = readAll(context)
        return mapOf(
            "limit" to limit(context),
            "total" to entries.size,
            "entries" to entries.map { toMap(it) }
        )
    }
}
