package com.pulseai.kashstash

import java.time.Instant

class RecentTagsManager {
    fun updateRecentTags(tags: String, config: KashStashConfig): KashStashConfig {
        if (tags.isBlank()) return config

        val timestamp = Instant.now().toString()
        val recentTags = config.recentTags.toMutableList()

        // Remove existing entry if it exists (we'll re-add with new timestamp)
        recentTags.removeAll { it.value == tags }

        // Add at beginning with new timestamp
        recentTags.add(0, RecentTag(tags, timestamp))

        // Keep only 50 most recent
        val trimmed = recentTags.take(50)

        // Return new config with updated tags
        return config.copy(recentTags = trimmed)
    }

    fun getRecentTagsList(config: KashStashConfig): List<RecentTag> {
        return config.recentTags.take(10)
    }
}