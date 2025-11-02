package com.pulseai.kashstash

data class KashStashConfig(
    val endpoints: List<EndpointConfig> = emptyList(),
    val lastUsedEndpoint: Int = 0,
    // NEW FIELDS:
    val kashFiles: List<KashFilesConfig> = emptyList(),
    val lastUsedKashFiles: Int = 0,
    val recentTags: List<RecentTag> = emptyList()
)