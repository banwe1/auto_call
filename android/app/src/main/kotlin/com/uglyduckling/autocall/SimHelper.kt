package com.uglyduckling.autocall

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
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

    /** 全部可通话账户（顺序即卡槽顺序：0=卡1、1=卡2） */
    fun accounts(context: Context): List<PhoneAccountHandle> {
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            ?: return emptyList()
        val list = try {
            tm.callCapablePhoneAccounts
        } catch (e: Exception) {
            null
        }
        return list ?: emptyList()
    }

    /** 跟随系统时的默认卡下标，找不到返回 -1 */
    fun defaultIndex(context: Context, accounts: List<PhoneAccountHandle>): Int {
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            ?: return -1
        val handle = try {
            tm.getDefaultOutgoingPhoneAccount("tel")
        } catch (e: Exception) {
            null
        } ?: return -1
        return accounts.indexOfFirst { it.id == handle.id }
    }

    /** 按模式解析本次拨号使用下标（-1 表示交给系统） */
    fun resolveIndex(context: Context, mode: Int): Int {
        val list = accounts(context)
        if (list.isEmpty()) return -1
        return when (mode) {
            DialPrefs.MODE_SIM1 -> 0
            DialPrefs.MODE_SIM2 -> if (list.size > 1) 1 else -1
            DialPrefs.MODE_ALTERNATE -> {
                var alt = DialPrefs.getAltIndex(context)
                if (alt < 0 || alt >= list.size) alt = 0
                DialPrefs.setAltIndex(context, if (alt == 0) 1 else 0)
                alt
            }
            else -> defaultIndex(context, list)
        }
    }

    /** 兼容模式：部分 ROM 需要这些 extra 指定卡槽 */
    private val COMPAT_KEYS = arrayOf(
        "subscription", "Subscription", "com.android.phone.extra.slot", "phone",
        "com.android.phone.DialingMode", "simId", "simnum", "phone_type", "simSlot"
    )

    /** 号码 + 该卡前缀（前缀依次轮换） */
    fun numberWithPrefix(context: Context, number: String, index: Int): String {
        if (index < 0) return number
        val prefix = DialPrefs.nextPrefix(context, index + 1)
        return if (prefix.isEmpty()) number else prefix + number
    }

    /** 用 TelecomManager.placeCall 直接拨号（后台也可用），返回 (是否成功, 使用卡下标) */
    fun placeCall(context: Context, number: String, mode: Int): Pair<Boolean, Int> {
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            ?: return Pair(false, -1)
        val list = accounts(context)
        val index = resolveIndex(context, mode)
        val finalNumber = numberWithPrefix(context, number, index)
        val extras = android.os.Bundle()
        if (index >= 0 && index < list.size) {
            extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, list[index])
        }
        return try {
            tm.placeCall(Uri.fromParts("tel", finalNumber, null), extras)
            Pair(true, index)
        } catch (e: Exception) {
            Pair(false, index)
        }
    }

    /** 兜底：ACTION_CALL 意图（含兼容模式 extra） */
    fun callIntent(context: Context, number: String, mode: Int): Intent {
        val list = accounts(context)
        val index = resolveIndex(context, mode)
        val finalNumber = numberWithPrefix(context, number, index)
        val intent = Intent(Intent.ACTION_CALL)
        if (index >= 0 && index < list.size) {
            if (DialPrefs.isCompatMode(context)) {
                for (key in COMPAT_KEYS) intent.putExtra(key, index)
            } else {
                intent.putExtra(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, list[index])
            }
        }
        intent.data = Uri.fromParts("tel", finalNumber, null)
        return intent
    }
}
