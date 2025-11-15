// File: pods/services/DigestReplyDetector.kt
package com.pulseai.kashstash.pods.services

import com.pulseai.kashstash.pods.models.Digest

class DigestReplyDetector(private val deviceNames: Set<String>) {

    fun analyzeDigests(digests: List<Digest>): List<Digest> {
        if (deviceNames.isEmpty()) return digests

        val analyzed = digests.toMutableList()
        val cleanDeviceNames = deviceNames.map { it.lowercase().replace(" ", "-") }.toSet()

        // First pass: identify my posts (from any of my devices)
        val myPostIds = digests
            .filter { digest ->
                cleanDeviceNames.any { deviceName ->
                    digest.tags.contains("from-$deviceName")
                }
            }
            .map { it.id }
            .toSet()

        // Mark my posts
        for (i in analyzed.indices) {
            val isMyPost = cleanDeviceNames.any { deviceName ->
                analyzed[i].tags.contains("from-$deviceName")
            }
            if (isMyPost) {
                analyzed[i] = analyzed[i].copy(isMyPost = true)
            }
        }

        // Second pass: identify replies to my posts
        for (i in analyzed.indices) {
            val replyToId = extractReplyId(analyzed[i].content)
            if (replyToId != null && myPostIds.contains(replyToId)) {
                analyzed[i] = analyzed[i].copy(
                    isReplyToMe = true,
                    repliesTo = replyToId
                )
            }

            // Also check if content mentions any of my devices
            val mentionsMe = cleanDeviceNames.any { deviceName ->
                analyzed[i].content.contains(".$deviceName")
            }
            if (mentionsMe) {
                analyzed[i] = analyzed[i].copy(isReplyToMe = true)
            }
        }

        return analyzed
    }

    private fun extractReplyId(content: String): String? {
        // Pattern: @reply:ID or >>ID or RE:ID
        val patterns = listOf(
            Regex("""@reply:([a-zA-Z0-9_-]+)"""),
            Regex(""">>([a-zA-Z0-9_-]+)"""),
            Regex("""RE:([a-zA-Z0-9_-]+)""")
        )

        for (pattern in patterns) {
            val match = pattern.find(content)
            if (match != null && match.groupValues.size > 1) {
                return match.groupValues[1]
            }
        }

        // Check for new format: @pod.node.digest.device
        val atIndex = content.indexOf("@")
        if (atIndex != -1) {
            val afterAt = content.substring(atIndex + 1)
            val endIndex = afterAt.indexOfFirst { it.isWhitespace() || it == '\n' }
                .let { if (it == -1) afterAt.length else it }
            val mention = afterAt.substring(0, endIndex)

            val components = mention.split(".")
            if (components.size >= 3) {
                // Third component is the digest ID
                return components[2]
            }
        }

        return null
    }
}