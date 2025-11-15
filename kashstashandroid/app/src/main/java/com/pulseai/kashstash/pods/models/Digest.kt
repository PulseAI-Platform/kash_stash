package com.pulseai.kashstash.pods.models

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.TypeConverters
import com.pulseai.kashstash.pods.storage.Converters
import java.util.Date

@Entity(tableName = "digests")
@TypeConverters(Converters::class)
data class Digest(
    @PrimaryKey
    val id: String,
    val title: String,
    val content: String,
    val tags: List<String> = emptyList(),
    val sourceNode: String? = null,
    val createdAt: Date,
    val inPods: List<String> = emptyList(),
    val isMyPost: Boolean = false,
    val isReplyToMe: Boolean = false,
    val repliesTo: String? = null,
    val replyToDevice: String? = null
) {
    // Computed property for reply detection
    val isReply: Boolean
        get() = content.contains("@[") || content.contains("@reply:")

    // Parse reply metadata from content
    fun parseReplyInfo(myDeviceName: String, myNodeName: String): Pair<Boolean, String?> {
        // Check for new format: @podname.probes-node-name.xyzpulseinfra.com.digestid.devicename
        val atIndex = content.indexOf("@")
        if (atIndex != -1) {
            val afterAt = content.substring(atIndex + 1)

            // Find the end of the mention (space or newline)
            val endIndex = afterAt.indexOfFirst { it.isWhitespace() || it == '\n' }
                .let { if (it == -1) afterAt.length else it }
            val mention = afterAt.substring(0, endIndex)

            // Split by dots to get components
            val components = mention.split(".")

            // Check if it has enough components and matches our device
            if (components.size >= 5) {
                val targetDevice = components.last()
                val isToMe = targetDevice.lowercase() ==
                        myDeviceName.lowercase().replace(" ", "-")
                return Pair(isToMe, targetDevice)
            }
        }

        // Fallback: check tags for device mentions
        val deviceTag = myDeviceName.lowercase().replace(" ", "-")
        if (tags.contains(deviceTag) && content.contains("@")) {
            return Pair(true, null)
        }

        return Pair(false, null)
    }

    // Computed property for Set operations
    val inPodsSet: Set<String>
        get() = inPods.toSet()
}