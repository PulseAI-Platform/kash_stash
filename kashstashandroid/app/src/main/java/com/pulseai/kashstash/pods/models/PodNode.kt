package com.pulseai.kashstash.pods.models

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.TypeConverters
import com.pulseai.kashstash.pods.storage.Converters
import java.util.Date
import java.util.UUID

@Entity(tableName = "pod_nodes")
@TypeConverters(Converters::class)
data class PodNode(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val nodeUrl: String,
    val name: String,
    val advertisedTags: List<String> = emptyList(),
    val status: String = "unknown",
    val lastSeen: Date? = null,

    // Notification preferences
    val notifyNewDigests: Boolean = false,
    val notifyReplies: Boolean = false,
    val lastSeenDigestId: String? = null,
    val lastSeenReplyId: String? = null,

    // Foreign key to parent pod
    val podConfigId: String
)