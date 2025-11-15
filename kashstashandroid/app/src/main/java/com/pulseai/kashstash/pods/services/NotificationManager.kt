package com.pulseai.kashstash.pods.services

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.pulseai.kashstash.MainActivity
import com.pulseai.kashstash.R
import com.pulseai.kashstash.pods.models.Digest
import com.pulseai.kashstash.pods.models.PodConfig
import com.pulseai.kashstash.pods.storage.PodPreferences

class NotificationManager(private val context: Context) {

    private val prefs = PodPreferences(context)
    private val notificationManager = NotificationManagerCompat.from(context)

    companion object {
        private const val CHANNEL_ID_DIGESTS = "pod_digests"
        private const val CHANNEL_ID_REPLIES = "pod_replies"
        private const val CHANNEL_NAME_DIGESTS = "Pod Digests"
        private const val CHANNEL_NAME_REPLIES = "Pod Replies"

        private const val NOTIFICATION_ID_DIGEST = 1001
        private const val NOTIFICATION_ID_REPLY = 1002
    }

    init {
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val digestChannel = NotificationChannel(
                CHANNEL_ID_DIGESTS,
                CHANNEL_NAME_DIGESTS,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifications for new posts in your pods"
            }

            val replyChannel = NotificationChannel(
                CHANNEL_ID_REPLIES,
                CHANNEL_NAME_REPLIES,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for replies to your posts"
            }

            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(digestChannel)
            manager.createNotificationChannel(replyChannel)
        }
    }

    fun hasPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notificationManager.areNotificationsEnabled()
        } else {
            true
        }
    }

    fun checkForNewContent(
        digests: List<Digest>,
        pod: PodConfig,
        deviceName: String
    ) {
        if (!hasPermission()) return

        val cleanDeviceName = deviceName.lowercase().replace(" ", "-")
        val sortedDigests = digests.sortedByDescending { it.createdAt }

        // Check for new digests (non-replies)
        if (pod.notifyNewDigests) {
            val newDigests = sortedDigests.filter { digest ->
                // Skip if it's a reply
                if (digest.repliesTo != null || digest.content.startsWith("@") || digest.tags.contains("reply")) {
                    return@filter false
                }

                // Skip if already notified
                if (prefs.wasNotified(digest.id, false)) {
                    return@filter false
                }

                // Skip if it's our own post
                if (digest.tags.contains("from-$cleanDeviceName")) {
                    return@filter false
                }

                // Skip if older than 24 hours
                if (System.currentTimeMillis() - digest.createdAt.time > 86400000) {
                    return@filter false
                }

                true
            }

            newDigests.take(5).forEach { digest ->
                sendNewDigestNotification(digest, pod)
                prefs.markAsNotified(digest.id, false)
            }
        }

        // Check for new replies
        if (pod.notifyReplies) {
            val newReplies = sortedDigests.filter { digest ->
                // Must be a reply
                if (digest.repliesTo == null && !digest.content.startsWith("@") && !digest.tags.contains("reply")) {
                    return@filter false
                }

                // Skip if already notified
                if (prefs.wasNotified(digest.id, true)) {
                    return@filter false
                }

                // Skip if it's our own reply
                if (digest.tags.contains("from-$cleanDeviceName")) {
                    return@filter false
                }

                // Check if it's a reply to us
                val isReplyToMe = digest.content.lowercase().contains(".$cleanDeviceName")

                // Skip if older than 24 hours
                if (System.currentTimeMillis() - digest.createdAt.time > 86400000) {
                    return@filter false
                }

                isReplyToMe
            }

            newReplies.take(5).forEach { reply ->
                sendReplyNotification(reply, pod)
                prefs.markAsNotified(reply.id, true)
            }
        }
    }

    private fun sendNewDigestNotification(digest: Digest, pod: PodConfig) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("podId", pod.id)
            putExtra("digestId", digest.id)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            digest.id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Extract author from tags
        val author = digest.tags.firstOrNull { it.startsWith("from-") }
            ?.removePrefix("from-") ?: "Someone"

        val preview = if (digest.title.isNotEmpty()) {
            digest.title
        } else {
            digest.content.take(100)
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID_DIGESTS)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle("New post in ${pod.name}")
            .setContentText("$author: $preview")
            .setStyle(NotificationCompat.BigTextStyle().bigText("$author: $preview"))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(NOTIFICATION_ID_DIGEST + digest.id.hashCode(), notification)
    }

    private fun sendReplyNotification(digest: Digest, pod: PodConfig) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("podId", pod.id)
            putExtra("digestId", digest.id)
            putExtra("isReply", true)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            digest.id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Extract who replied
        val replier = digest.tags.firstOrNull { it.startsWith("from-") }
            ?.removePrefix("from-") ?: "Someone"

        // Clean the content (remove @mention prefix)
        var cleanContent = digest.content
        val firstSpace = cleanContent.indexOf(" ")
        if (firstSpace != -1) {
            cleanContent = cleanContent.substring(firstSpace + 1)
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID_REPLIES)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle("New reply in ${pod.name}")
            .setContentText("$replier replied: ${cleanContent.take(100)}")
            .setStyle(NotificationCompat.BigTextStyle().bigText("$replier replied: $cleanContent"))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(NOTIFICATION_ID_REPLY + digest.id.hashCode(), notification)
    }

    fun clearAllNotifications() {
        notificationManager.cancelAll()
    }

    fun cleanupOldRecords() {
        prefs.cleanupOldNotificationRecords()
    }
}