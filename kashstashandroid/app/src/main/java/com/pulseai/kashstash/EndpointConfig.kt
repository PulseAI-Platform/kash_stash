package com.pulseai.kashstash

data class EndpointConfig(
    val name: String,
    val device: String,
    val probeKey: String,
    val nodeName: String,
    val probeId: String,
    // NEW FIELDS:
    val configDigestId: String = "",
    val configDigestTags: String = "agent-config",
    val configCacheMinutes: Int = 5
)