package com.pulseai.kashstash.pods.services

import com.pulseai.kashstash.pods.models.Digest

class DigestReplyDetector(private val deviceName: String) {

    fun analyzeDigests(digests: List<Digest>): List<Digest> {
        val analyzed = digests.toMutableList()
        val cleanDeviceName = deviceName.lowercase().replace(" ", "-")

        // First pass: identify my posts
        val myPostIds = digests
            .filter { it.tags.contains("from-$cleanDeviceName") }
            .map { it.id }
            .toSet()

        // Mark my posts
        for (i in analyzed.indices) {
            if (analyzed[i].tags.contains("from-$cleanDeviceName")) {
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

            // Also check if content mentions my device
            if (analyzed[i].content.contains(".$cleanDeviceName")) {
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