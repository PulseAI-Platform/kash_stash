package com.pulseai.kashstash.pods.storage

import android.content.Context
import android.content.SharedPreferences

class PodPreferences(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("pod_preferences", Context.MODE_PRIVATE)

    companion object {
        private const val KEY_NOTIFIED_DIGEST_IDS = "notified_digest_ids"
        private const val KEY_NOTIFIED_REPLY_IDS = "notified_reply_ids"
        private const val KEY_LAST_SYNC_TIME = "last_sync_time"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val KEY_NODE_NAME = "node_name"
    }

    // Notification tracking
    fun wasNotified(digestId: String, isReply: Boolean): Boolean {
        val key = if (isReply) KEY_NOTIFIED_REPLY_IDS else KEY_NOTIFIED_DIGEST_IDS
        val notifiedIds = getNotifiedIds(key)
        return notifiedIds.contains(digestId)
    }

    fun markAsNotified(digestId: String, isReply: Boolean) {
        val key = if (isReply) KEY_NOTIFIED_REPLY_IDS else KEY_NOTIFIED_DIGEST_IDS
        val notifiedIds = getNotifiedIds(key).toMutableSet()
        notifiedIds.add(digestId)

        // Keep only last 1000 IDs
        val trimmedIds = if (notifiedIds.size > 1000) {
            notifiedIds.toList().takeLast(1000).toSet()
        } else {
            notifiedIds
        }

        prefs.edit().putStringSet(key, trimmedIds).apply()
    }

    private fun getNotifiedIds(key: String): Set<String> {
        return prefs.getStringSet(key, emptySet()) ?: emptySet()
    }

    fun cleanupOldNotificationRecords() {
        val digestIds = getNotifiedIds(KEY_NOTIFIED_DIGEST_IDS)
        val replyIds = getNotifiedIds(KEY_NOTIFIED_REPLY_IDS)

        if (digestIds.size > 500) {
            prefs.edit().putStringSet(
                KEY_NOTIFIED_DIGEST_IDS,
                digestIds.toList().takeLast(500).toSet()
            ).apply()
        }

        if (replyIds.size > 500) {
            prefs.edit().putStringSet(
                KEY_NOTIFIED_REPLY_IDS,
                replyIds.toList().takeLast(500).toSet()
            ).apply()
        }
    }

    // Sync tracking
    var lastSyncTime: Long
        get() = prefs.getLong(KEY_LAST_SYNC_TIME, 0)
        set(value) = prefs.edit().putLong(KEY_LAST_SYNC_TIME, value).apply()

    // Device info
    var deviceName: String?
        get() = prefs.getString(KEY_DEVICE_NAME, null)
        set(value) = prefs.edit().putString(KEY_DEVICE_NAME, value).apply()

    var nodeName: String?
        get() = prefs.getString(KEY_NODE_NAME, null)
        set(value) = prefs.edit().putString(KEY_NODE_NAME, value).apply()
}