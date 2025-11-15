package com.pulseai.kashstash.pods.models

import com.pulseai.kashstash.pods.services.FeedEntry
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

fun FeedEntry.toDigest(): Digest {
    // Parse the date string
    val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
    val createdDate = try {
        // Handle the microseconds in the date string
        val dateStr = created.substringBefore(".")
        dateFormat.parse(dateStr) ?: Date()
    } catch (e: Exception) {
        Date()
    }

    // Extract tag names from TagInfo objects
    val tagNames = tags.map { it.name }

    return Digest(
        id = id.toString(),  // Convert Int to String
        title = "",  // No title field in the response
        content = content,
        tags = tagNames,  // Now this is List<String>
        sourceNode = sourceNode,
        createdAt = createdDate,
        inPods = emptyList(),
        isMyPost = false,
        isReplyToMe = false,
        repliesTo = null,
        replyToDevice = null
    )
}