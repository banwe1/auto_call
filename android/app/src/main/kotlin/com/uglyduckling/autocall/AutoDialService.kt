package com.uglyduckling.autocall

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray

/**
 * 自动连拨前台服务：队列拨号、等待通话结束、间隔倒计时、回到 App。
 * 放在原生层是为了 App 退到后台/锁屏后依然继续拨号。
 */
class AutoDialService : Service() {

    companion object {
        const val ACTION_START = "com.uglyduckling.autocall.dial.START"
        const val ACTION_STOP = "com.uglyduckling.autocall.dial.STOP"
        const val ACTION_PAUSE = "com.uglyduckling.autocall.dial.PAUSE"
        const val ACTION_RESUME = "com.uglyduckling.autocall.dial.RESUME"
        const val ACTION_SKIP_NEXT = "com.uglyduckling.autocall.dial.SKIP_NEXT"
        const val ACTION_REDIAL = "com.uglyduckling.autocall.dial.REDIAL"
        const val ACTION_REMOVE_NEXT = "com.uglyduckling.autocall.dial.REMOVE_NEXT"
        const val EXTRA_QUEUE = "queue"

        private const val CHANNEL_ID = "auto_dial_service"
        private const val NOTIFICATION_ID = 1024
        private const val CALL_TIMEOUT_MS = 90_000L

        @Volatile
        var running = false
            private set

        @Volatile
        var paused = false
            private set

        @Volatile
        var index = 0
            private set

        @Volatile
        var total = 0
            private set

        @Volatile
        var currentPhone: String? = null
            private set

        @Volatile
        var statusText: String = "空闲"
            private set

        @Volatile
        var connectedCount = 0
            private set

        /** 是否因「拨打个数提醒」而暂停（供 Flutter 弹「继续 / 停止」） */
        @Volatile
        var reminder = false
            private set

        @Volatile
        var lastResult: Map<String, Any?>? = null

        @Volatile
        var eventSink: EventChannel.EventSink? = null

        /** App 是否在前台（由 MainActivity 的 onResume/onPause 维护） */
        @Volatile
        private var appVisible: Boolean = false

        @Volatile
        private var serviceRef: AutoDialService? = null

        /** App 回到前台 → 继续倒计时 */
        fun onAppForeground() {
            appVisible = true
            serviceRef?.onAppVisible()
        }

        /** App 离开前台 → 冻结倒计时 */
        fun onAppBackground() {
            appVisible = false
        }

        fun isAppVisible(): Boolean = appVisible

        fun statusMap(): Map<String, Any?> {
            // 服务实例存在时，带上倒计时 / 阶段 / 下一个号码等运行时信息
            val ref = serviceRef
            if (ref != null) {
                try {
                    return ref.buildStatus()
                } catch (e: Exception) {
                    // 回落到静态状态
                }
            }
            return mapOf(
                "running" to running,
                "paused" to paused,
                "index" to index,
                "total" to total,
                "phone" to currentPhone,
                "status" to statusText,
                "connected" to connectedCount,
                "reminder" to reminder,
                "countdown" to 0,
                "phase" to "idle",
                "nextPhone" to null,
                "lastResult" to lastResult
            )
        }

        fun emit() {
            val sink = eventSink ?: return
            try {
                sink.success(statusMap())
            } catch (e: Exception) {
                // Flutter 已断开
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val queue = mutableListOf<String>()
    private var callWatcher: CallStateWatcher? = null
    private var sawActive = false
    private var currentIndex = -1
    private var countdown = 0
    private var countingDown = false
    private var waitingForApp = false
    private var dialStartedAt = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        serviceRef = this
        createChannel()
    }

    /** App 回到前台时调用：若正在等待前台，则从剩余秒数继续 */
    fun onAppVisible() {
        if (!running || paused) return
        if (!countingDown || !waitingForApp) return
        waitingForApp = false
        statusText = "$countdown 秒后拨打下一个"
        updateNotification()
        emit()
        tick()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startDialing(intent.getStringExtra(EXTRA_QUEUE))
            ACTION_PAUSE -> {
                paused = true
                reminder = false
                statusText = "已暂停"
                updateNotification()
                emit()
            }
            ACTION_RESUME -> {
                if (running && paused) {
                    paused = false
                    reminder = false
                    if (countingDown) tick() else step()
                }
            }
            ACTION_STOP -> stopDialing("已停止")
            ACTION_SKIP_NEXT -> skipToNext()
            ACTION_REDIAL -> redialCurrent()
            ACTION_REMOVE_NEXT -> removeNextPhone()
        }
        return START_NOT_STICKY
    }

    private fun startDialing(queueJson: String?) {
        queue.clear()
        if (!queueJson.isNullOrEmpty()) {
            try {
                val array = JSONArray(queueJson)
                for (i in 0 until array.length()) {
                    val value = array.optString(i)
                    if (value.isNotBlank()) queue.add(value)
                }
            } catch (e: Exception) {
                // 队列解析失败
            }
        }
        total = queue.size
        if (queue.isEmpty()) {
            stopDialing("没有号码")
            return
        }
        index = 0
        connectedCount = 0
        running = true
        paused = false
        reminder = false
        countingDown = false
        waitingForApp = false
        appVisible = true
        lastResult = null
        startForeground(NOTIFICATION_ID, buildNotification("准备拨号"))
        emit()
        step()
    }

    private fun step() {
        if (!running || paused) return
        if (index >= queue.size) {
            stopDialing("本批次拨号完成")
            return
        }

        val phone = queue[index]
        currentIndex = index
        currentPhone = phone
        statusText = "正在拨打 $phone"
        updateNotification()
        emit()

        val mode = DialPrefs.getMode(this)
        dialStartedAt = System.currentTimeMillis()
        val result = SimHelper.placeCall(this, phone, mode)
        if (!result.first) {
            fallbackCall(phone, mode)
        }
        statusText =
            if (result.second >= 0) "正在拨打（卡${result.second + 1}）" else "正在拨打"
        updateNotification()
        emit()
        waitForCallEnd()
    }

    /** placeCall 失败时用 ACTION_CALL 兜底（借无障碍服务启动，避免后台限制） */
    private fun fallbackCall(phone: String, mode: Int) {
        try {
            val intent = SimHelper.callIntent(this, phone, mode)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val a11y = AutoDialAccessibilityService.instance
            if (a11y != null) a11y.startActivity(intent) else startActivity(intent)
        } catch (e: Exception) {
            statusText = "拨号失败：${e.message}"
            updateNotification()
            emit()
        }
    }

    private fun waitForCallEnd() {
        sawActive = false
        callWatcher?.stop()
        callWatcher = CallStateWatcher(this) { payload ->
            val state = payload["state"] as? String
            when (state) {
                "offhook", "ringing" -> {
                    sawActive = true
                    statusText = "通话中 ${currentPhone ?: ""}"
                    updateNotification()
                    emit()
                }
                "idle" -> {
                    if (sawActive) {
                        val connected = payload["connected"] as? Boolean ?: false
                        val duration = (payload["durationSec"] as? Number)?.toInt() ?: 0
                        onCallEnded(connected, duration)
                    }
                }
            }
        }
        callWatcher?.start()
        handler.postDelayed(timeoutRunnable, CALL_TIMEOUT_MS)
    }

    private val timeoutRunnable = Runnable {
        if (!running) return@Runnable
        AutoDialAccessibilityService.requestHangup()
        handler.postDelayed({
            if (running && sawActive) onCallEnded(false, 0)
        }, 3000L)
    }

    /** 当前活跃批次（Flutter 侧写入 shared_preferences 的 active_batch_id / _name） */
    private fun activeBatch(): Pair<String, String> {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val id = prefs.getString("flutter.active_batch_id", null).orEmpty()
            val name = prefs.getString("flutter.active_batch_name", null).orEmpty()
            id to name
        } catch (e: Exception) {
            "" to ""
        }
    }

    private fun onCallEnded(connected: Boolean, durationSec: Int) {
        handler.removeCallbacks(timeoutRunnable)
        callWatcher?.stop()
        callWatcher = null
        sawActive = false

        val phone = currentPhone ?: ""
        if (connected) connectedCount++
        val dialSec = if (dialStartedAt > 0) {
            ((System.currentTimeMillis() - dialStartedAt) / 1000L).toInt()
        } else {
            0
        }
        DialStats.recordCall(this, connected, durationSec, dialSec)
        // 写入拨号记录（自动连拨来源）
        val batch = activeBatch()
        DialHistory.add(
            this,
            DialHistory.Entry(
                number = phone,
                connected = connected,
                talkSec = durationSec,
                dialSec = dialSec,
                at = System.currentTimeMillis(),
                batchId = batch.first,
                batchName = batch.second,
                source = DialHistory.SOURCE_AUTO
            )
        )
        lastResult = mapOf(
            "phone" to phone,
            "connected" to connected,
            "durationSec" to durationSec
        )
        index++
        statusText = if (connected) "已接通 $durationSec 秒" else "未接通"
        updateNotification()
        emit()

        if (DialPrefs.isReturnToApp(this)) {
            AutoDialAccessibilityService.bringAppToFront()
        }

        if (!DialPrefs.isAutoNext(this)) {
            stopDialing("已停止（未开启自动下一个）")
            return
        }

        // 拨打个数提醒：每拨完 N 个自动暂停，等用户在 App 内确认继续
        val remindEvery = DialPrefs.getRemindEvery(this)
        if (remindEvery > 0 && index % remindEvery == 0 && index < queue.size) {
            paused = true
            reminder = true
            countingDown = false
            countdown = 0
            statusText = "已拨打 $index 个，等待继续"
            updateNotification()
            emit()
            return
        }

        scheduleNext()
    }

    private fun scheduleNext() {
        if (!running) return
        if (index >= queue.size) {
            stopDialing("本批次拨号完成")
            return
        }
        countdown = DialPrefs.getIntervalSec(this).coerceIn(1, 120)
        countingDown = true
        tick()
    }

    private fun tick() {
        if (!running || paused) return

        // 固定行为：App 不在前台时冻结倒计时（回到 App 后从剩余秒数继续）
        if (!appVisible) {
            if (!waitingForApp) {
                waitingForApp = true
                statusText = "已暂停（回到 App 继续）"
                updateNotification()
                emit()
            }
            return
        }
        waitingForApp = false

        if (countdown <= 0) {
            countingDown = false
            step()
            return
        }
        statusText = "$countdown 秒后拨打下一个"
        updateNotification()
        emit()
        countdown--
        handler.postDelayed({ tick() }, 1000L)
    }

    private fun stopDialing(message: String) {
        running = false
        paused = false
        reminder = false
        countdown = 0
        countingDown = false
        handler.removeCallbacksAndMessages(null)
        callWatcher?.stop()
        callWatcher = null
        statusText = message
        emit()
        try {
            stopForeground(true)
        } catch (e: Exception) {
            // ignore
        }
        stopSelf()
    }

    /** 完整运行状态（供 Flutter 运行页使用） */
    private fun buildStatus(): Map<String, Any?> = mapOf(
        "running" to running,
        "paused" to paused,
        "index" to index,
        "total" to total,
        "phone" to currentPhone,
        "status" to statusText,
        "connected" to connectedCount,
        "reminder" to reminder,
        "countdown" to if (countingDown) countdown else 0,
        "phase" to phaseName(),
        "nextPhone" to nextPhoneValue(),
        "lastResult" to lastResult
    )

    /** 运行阶段：idle / dialing / talking / countdown / waiting_app / paused / reminder */
    private fun phaseName(): String {
        if (!running) return "idle"
        if (reminder) return "reminder"
        if (paused) return "paused"
        if (countingDown) return if (waitingForApp) "waiting_app" else "countdown"
        return if (sawActive) "talking" else "dialing"
    }

    /** 「下一个」预览号码 */
    private fun nextPhoneValue(): String? {
        val nextIndex = if (currentIndex >= 0) currentIndex + 1 else index
        return queue.getOrNull(nextIndex)
    }

    /** 取消正在进行的倒计时/通话监听 */
    private fun resetPendingCall() {
        handler.removeCallbacksAndMessages(null)
        countingDown = false
        countdown = 0
        callWatcher?.stop()
        callWatcher = null
        sawActive = false
    }

    /** 下一个：通话中先挂断当前；倒计时中直接跳过下一个号码 */
    private fun skipToNext() {
        if (!running) return
        val wasDialing = !countingDown && currentPhone != null
        if (wasDialing) AutoDialAccessibilityService.requestHangup()
        resetPendingCall()
        paused = false
        reminder = false
        index += 1
        updateNotification()
        emit()
        step()
    }

    /** 重拨当前号码 */
    private fun redialCurrent() {
        if (!running) return
        val target = currentIndex
        if (target !in queue.indices) return
        val wasDialing = !countingDown && currentPhone != null
        if (wasDialing) AutoDialAccessibilityService.requestHangup()
        resetPendingCall()
        paused = false
        reminder = false
        index = target
        updateNotification()
        emit()
        step()
    }

    /** 删除「下一个」号码 */
    private fun removeNextPhone() {
        if (!running) return
        val nextIndex = if (currentIndex >= 0) currentIndex + 1 else index
        if (nextIndex !in queue.indices) return
        queue.removeAt(nextIndex)
        total = queue.size
        updateNotification()
        emit()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        callWatcher?.stop()
        running = false
        serviceRef = null
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "自动拨号",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.setShowBadge(false)
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, AutoDialService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val toggleIntent = PendingIntent.getService(
            this,
            2,
            Intent(this, AutoDialService::class.java)
                .setAction(if (paused) ACTION_RESUME else ACTION_PAUSE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val position = (index + 1).coerceAtMost(queue.size)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("自动拨号 $position/${queue.size}")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .addAction(0, if (paused) "继续" else "暂停", toggleIntent)
            .addAction(0, "停止", stopIntent)
            .build()
    }

    private fun updateNotification() {
        if (!running) return
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, buildNotification(statusText))
        } catch (e: Exception) {
            // ignore
        }
    }
}
