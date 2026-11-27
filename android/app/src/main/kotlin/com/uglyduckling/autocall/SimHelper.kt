package com.uglyduckling.autocall

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat

/**
 * 双卡（Subscription）与通话账户（PhoneAccountHandle）的映射工具。
 */
object SimHelper {

    fun hasPermission(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /** 读取当前插入的 SIM 列表（需要 READ_PHONE_STATE） */
    fun listSims(context: Context): List<Map<String, Any?>> {
        if (!hasPermission(context, Manifest.permission.READ_PHONE_STATE)) return emptyList()
        val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            ?: return emptyList()
        val infos = try {
            sm.activeSubscriptionInfoList
        } catch (e: Exception) {
            null
        } ?: return emptyList()

        return infos.map { info ->
            mapOf(
                "subscriptionId" to info.subscriptionId,
                "slotIndex" to info.simSlotIndex,
                "displayName" to (info.displayName?.toString() ?: ""),
                "carrierName" to (info.carrierName?.toString() ?: "")
            )
        }
    }

    /** 把 subscriptionId 映射成 Telecom 的 PhoneAccountHandle */
    fun phoneAccountFor(context: Context, subscriptionId: Int): PhoneAccountHandle? {
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return null
        val accounts = try {
            tm.callCapablePhoneAccounts
        } catch (e: Exception) {
            null
        } ?: return null

        // 常见情况：PhoneAccountHandle.id 就是 subscriptionId
        accounts.firstOrNull { it.id == subscriptionId.toString() }?.let { return it }

        // 兜底：按订阅在列表中的顺序对应通话账户
        val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
        val infos = try {
            sm?.activeSubscriptionInfoList
        } catch (e: Exception) {
            null
        } ?: emptyList()
        val index = infos.indexOfFirst { it.subscriptionId == subscriptionId }
        return if (index >= 0 && index < accounts.size) accounts[index] else null
    }
}
