package com.uglyduckling.autocall

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * 自动拨号辅助服务：只在通话界面里找「挂断」按钮并点击。
 * 需要用户在系统设置里手动开启。
 */
class AutoDialAccessibilityService : AccessibilityService() {

    companion object {
        /** 各 ROM 拨号器的挂断按钮文案 */
        private val HANGUP_TEXTS = arrayOf(
            "挂断", "结束通话", "结束", "挂断电话", "结束呼叫", "取消"
        )

        @Volatile
        var instance: AutoDialAccessibilityService? = null
            private set

        @Volatile
        private var pendingHangup: Boolean = false

        /** 请求挂断（由 Flutter 触发） */
        fun requestHangup(): Boolean {
            val service = instance ?: return false
            pendingHangup = true
            service.tryHangup()
            return true
        }

        fun isConnected(): Boolean = instance != null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        val info = serviceInfo ?: AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPES_ALL_MASK
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.flags = info.flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        info.notificationTimeout = 100
        serviceInfo = info
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!pendingHangup) return
        tryHangup()
    }

    override fun onInterrupt() {
        // nothing
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    private fun tryHangup() {
        val root: AccessibilityNodeInfo = rootInActiveWindow ?: return
        for (text in HANGUP_TEXTS) {
            val nodes = try {
                root.findAccessibilityNodeInfosByText(text)
            } catch (e: Exception) {
                null
            } ?: continue
            for (node in nodes) {
                if (clickNodeOrParent(node)) {
                    pendingHangup = false
                    return
                }
            }
        }
    }

    /** 节点本身不可点击时，向上找可点击的父节点再点 */
    private fun clickNodeOrParent(node: AccessibilityNodeInfo?): Boolean {
        var current = node
        var depth = 0
        while (current != null && depth < 6) {
            if (current.isClickable) {
                if (current.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
            }
            current = current.parent
            depth++
        }
        return false
    }
}
