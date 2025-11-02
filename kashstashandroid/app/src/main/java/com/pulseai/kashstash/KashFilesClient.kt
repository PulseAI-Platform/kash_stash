package com.pulseai.kashstash

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONObject
import java.io.File

class KashFilesClient(private val config: KashFilesConfig) {
    private val client = OkHttpClient()

    suspend fun uploadFile(
        filename: String,
        fileData: ByteArray,
        contentType: String,
        tags: String,
        description: String
    ): KashFilesUploadResult = withContext(Dispatchers.IO) {
        try {
            // Create temp file for multipart upload
            val tempFile = File.createTempFile("upload", filename)
            tempFile.writeBytes(fileData)

            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(
                    "file",
                    filename,
                    tempFile.asRequestBody(contentType.toMediaTypeOrNull())
                )
                .addFormDataPart("tags", tags)
                .addFormDataPart("description", description)
                .build()

            val request = Request.Builder()
                .url("${config.url}/api/files/upload")
                .header("x-upload-key", config.key)
                .post(requestBody)
                .build()

            val response = client.newCall(request).execute()
            val responseBody = response.body?.string() ?: ""

            tempFile.delete()

            if (response.isSuccessful) {
                val json = JSONObject(responseBody)
                KashFilesUploadResult(
                    ok = json.optBoolean("ok", false),
                    download = json.optString("download", null),
                    error = null
                )
            } else {
                KashFilesUploadResult(
                    ok = false,
                    download = null,
                    error = "HTTP ${response.code}: $responseBody"
                )
            }
        } catch (e: Exception) {
            KashFilesUploadResult(
                ok = false,
                download = null,
                error = e.message
            )
        }
    }

    suspend fun testConnection(): Boolean = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url("${config.url}/api/health")
                .header("Authorization", "Bearer ${config.key}")
                .build()

            val response = client.newCall(request).execute()
            response.isSuccessful
        } catch (e: Exception) {
            false
        }
    }
}