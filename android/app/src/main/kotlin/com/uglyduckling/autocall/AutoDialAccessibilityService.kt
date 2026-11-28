package com.uglyduckling.autocall

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
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

        /** 各 ROM 通话界面的「录音」按钮文案 */
        private val RECORD_TEXTS = arrayOf(
            "录音", "开始录音", "通话录音", "录制", "录音机"
        )

        /** 展开「更多」菜单用的文案 */
        private val MORE_TEXTS = arrayOf("更多", "更多选项", "更多功能")

        @Volatile
        var instance: AutoDialAccessibilityService? = null
            private set

        @Volatile
        private var pendingHangup: Boolean = false

        @Volatile
        private var pendingRecord: Boolean = false

        @Volatile
        private var recordMoreExpanded: Boolean = false

        /** 请求挂断（由 Flutter 触发） */
        fun requestHangup(): Boolean {
            val service = instance ?: return false
            pendingHangup = true
            service.tryHangup()
            return true
        }

        /** 请求开始录音：点系统通话界面上的「录音」按钮 */
        fun requestStartRecording(): Boolean {
            val service = instance ?: return false
            pendingRecord = true
            recordMoreExpanded = false
            service.tryStartRecording()
            return true
        }

        fun isConnected(): Boolean = instance != null

        /**
         * 把 App 主界面拉到前台。
         * 无障碍服务不受 Android 10+ 后台启动 Activity 限制，故用它来"挂断后回到 App"。
         */
        fun bringAppToFront(): Boolean {
            val service = instance ?: return false
            return try {
                val intent = Intent(service, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                }
                service.startActivity(intent)
                true
            } catch (e: Exception) {
                false
            }
        }
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
        if (pendingHangup) tryHangup()
        if (pendingRecord) tryStartRecording()
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

    /** 找「录音」按钮并点击；找不到时展开「更多」再试一次 */
    private fun tryStartRecording() {
        val root: AccessibilityNodeInfo = rootInActiveWindow ?: return
        if (clickFirst(root, RECORD_TEXTS)) {
            pendingRecord = false
            return
        }
        if (!recordMoreExpanded) {
            recordMoreExpanded = true
            clickFirst(root, MORE_TEXTS)
        }
    }

    /** 按文案列表依次查找并点击，成功返回 true */
    private fun clickFirst(root: AccessibilityNodeInfo, texts: Array<String>): Boolean {
        for (text in texts) {
            val nodes = try {
                root.findAccessibilityNodeInfosByText(text)
            } catch (e: Exception) {
                null
            } ?: continue
            for (node in nodes) {
                if (clickNodeOrParent(node)) return true
            }
        }
        return false
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
