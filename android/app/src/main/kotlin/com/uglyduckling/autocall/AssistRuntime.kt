package com.uglyduckling.autocall

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager

/**
 * 通话辅助运行时：自动扬声器、自动录音（点系统录音按钮）、
 * 未接通超时挂断、已接通超时挂断。自动连拨与手动拨号共用。
 */
object AssistRuntime {

    private val handler = Handler(Looper.getMainLooper())
    private var unansweredRunnable: Runnable? = null
    private var answeredRunnable: Runnable? = null
    private var recordRunnable: Runnable? = null
    private var connected = false

    /** 拨出开始（启动「未接通超时」计时） */
    fun onDialStarted(context: Context) {
        val ctx = context.applicationContext
        cancelTimers()
        connected = false
        if (!AssistPrefs.isHangupUnanswered(ctx)) return
        val runnable = Runnable {
            if (!connected) hangup(ctx)
        }
        unansweredRunnable = runnable
        handler.postDelayed(runnable, AssistPrefs.getUnansweredSec(ctx) * 1000L)
    }

    /** 系统通话状态变为 offhook（视为接通） */
    fun onConnected(context: Context) {
        val ctx = context.applicationContext
        if (connected) return
        connected = true
        unansweredRunnable?.let { handler.removeCallbacks(it) }
        unansweredRunnable = null

        if (AssistPrefs.isAutoSpeaker(ctx)) enableSpeaker(ctx)

        if (AssistPrefs.isAutoRecord(ctx)) {
            val runnable = Runnable { AutoDialAccessibilityService.requestStartRecording() }
            recordRunnable = runnable
            handler.postDelayed(runnable, 1500L)
        }

        if (AssistPrefs.isHangupAnswered(ctx)) {
            val runnable = Runnable { hangup(ctx) }
            answeredRunnable = runnable
            handler.postDelayed(runnable, AssistPrefs.getAnsweredSec(ctx) * 1000L)
        }
    }

    /** 通话结束 */
    fun onIdle() {
        cancelTimers()
        connected = false
    }

    private fun cancelTimers() {
        unansweredRunnable?.let { handler.removeCallbacks(it) }
        answeredRunnable?.let { handler.removeCallbacks(it) }
        recordRunnable?.let { handler.removeCallbacks(it) }
        unansweredRunnable = null
        answeredRunnable = null
        recordRunnable = null
    }

    private fun enableSpeaker(context: Context) {
        try {
            val manager =
                context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            manager.isSpeakerphoneOn = true
        } catch (e: Exception) {
            // 缺少 MODIFY_AUDIO_SETTINGS 或被系统限制时忽略
        }
    }

    /** 挂断：优先无障碍点「挂断」，失败回退 TelecomManager.endCall() */
    private fun hangup(context: Context) {
        if (AutoDialAccessibilityService.requestHangup()) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val telecom =
                    context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                        ?: return
                telecom.endCall()
            }
        } catch (e: Exception) {
            // 缺少 ANSWER_PHONE_CALLS 时忽略
        }
    }
}
