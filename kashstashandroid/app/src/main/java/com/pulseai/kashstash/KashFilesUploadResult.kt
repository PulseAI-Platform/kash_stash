package com.pulseai.kashstash

data class KashFilesUploadResult(
    val ok: Boolean,
    val download: String? = null, // relative path like "/download/abc123"
    val error: String? = null
)