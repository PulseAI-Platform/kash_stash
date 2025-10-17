package com.pulseai.kashstash

data class EndpointConfig(
    val name: String,
    val device: String,
    val probeKey: String,
    val nodeName: String,
    val probeId: String
)