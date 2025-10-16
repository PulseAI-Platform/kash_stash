package com.pulseai.kashstash

data class KashStashConfig(
    val endpoints: List<EndpointConfig> = emptyList(),
    val lastUsedEndpoint: Int = 0
)