package com.pulseai.kashstash.pods.models

import com.google.gson.annotations.SerializedName
import java.util.Date
// Response from advertise endpoint
data class AdvertiseResponse(
    @SerializedName("node_name")
    val nodeName: String,
    @SerializedName("advertised_tags")
    val advertisedTags: List<String>,
    val nodes: List<NodeInfo>
) {
    data class NodeInfo(
        val url: String,
        val name: String
    )
}

// Response from digests endpoint
data class DigestsResponse(
    val feedentries: List<DigestEntry>,
    val total: Int,
    val page: Int,
    val pages: Int
) {
    data class DigestEntry(
        val id: Int,
        val title: String?,
        val content: String?,
        val tags: List<Tag>?,
        @SerializedName("source_node")
        val sourceNode: String?,
        @SerializedName("created")
        val createdAt: String?
    ) {
        data class Tag(
            val id: Int,
            val name: String,
            val created: String
        )
    }
}

// Extension to convert API response to Digest model
fun DigestsResponse.DigestEntry.toDigest(): Digest {
    return Digest(
        id = this.id.toString(),
        title = this.title ?: "",
        content = this.content ?: "",
        tags = this.tags?.map { it.name } ?: emptyList(),
        sourceNode = this.sourceNode,
        createdAt = parseISODate(this.createdAt),
        inPods = emptyList(),
        isMyPost = false,
        isReplyToMe = false,
        repliesTo = null
    )
}

// Helper to parse ISO date
private fun parseISODate(dateStr: String?): Date {
    if (dateStr == null) return Date()

    return try {
        // Try parsing with different formats
        val formats = listOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss"
        )

        for (format in formats) {
            try {
                val sdf = java.text.SimpleDateFormat(format, java.util.Locale.US)
                sdf.timeZone = java.util.TimeZone.getTimeZone("UTC")
                return sdf.parse(dateStr) ?: Date()
            } catch (e: Exception) {
                continue
            }
        }
        Date()
    } catch (e: Exception) {
        Date()
    }
}

// QR Code import format
data class PodQRConfig(
    val name: String,
    val entrance_url: String,
    val preshared_key: String,
    val tags: List<String>
)