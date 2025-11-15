package com.pulseai.kashstash.pods.models

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.TypeConverters
import com.pulseai.kashstash.pods.storage.Converters
import java.util.Date
import java.util.UUID

@Entity(tableName = "pod_configs")
data class PodConfig(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val entranceNodeUrl: String,
    val presharedKey: String,
    val cachedTags: List<String> = emptyList(),
    val discoveredTags: List<String> = emptyList(),
    val discoveredNodes: List<PodNode> = emptyList(),
    val isActive: Boolean = true,
    val lastRefresh: Long = 0,
    val notifyNewDigests: Boolean = true,
    val notifyReplies: Boolean = true,
    val createdAt: Long = System.currentTimeMillis()
) {
    // Computed properties for Set operations
    val cachedTagsSet: Set<String>
        get() = cachedTags.toSet()

    val discoveredTagsSet: Set<String>
        get() = discoveredTags.toSet()

    // All available tags (advertised + discovered)
    val allTags: List<String>
        get() = (cachedTags + discoveredTags).toSet().sorted()

    val allTagsSet: Set<String>
        get() = (cachedTags + discoveredTags).toSet()
}