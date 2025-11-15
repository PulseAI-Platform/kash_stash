package com.pulseai.kashstash.pods.services

import com.pulseai.kashstash.pods.models.*
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class PodClient {

    private val okHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .addInterceptor(HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BODY
        })
        .build()

    private fun createService(baseUrl: String): PodApiService {
        // Ensure URL has /api/pods/ suffix
        val cleanUrl = when {
            baseUrl.endsWith("/api/pods/") -> baseUrl
            baseUrl.endsWith("/api/pods") -> "$baseUrl/"
            baseUrl.endsWith("/") -> "${baseUrl}api/pods/"
            else -> "$baseUrl/api/pods/"
        }

        Log.d("PodClient", "Creating service with base URL: $cleanUrl")

        val retrofit = Retrofit.Builder()
            .baseUrl(cleanUrl)
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()

        return retrofit.create(PodApiService::class.java)
    }

    suspend fun discoverNodes(pod: PodConfig): List<PodNode> {
        val service = createService(pod.entranceNodeUrl)

        Log.d("PodClient", "Discovering nodes for: ${pod.name}")
        Log.d("PodClient", "Entrance URL: ${pod.entranceNodeUrl}")

        return try {
            val response = service.advertise(
                podKey = pod.presharedKey
            )

            Log.d("PodClient", "Got response with ${response.nodes.size} nodes")
            Log.d("PodClient", "Available tags: ${response.advertisedTags.joinToString(",")}")

            response.nodes.map { nodeInfo ->
                PodNode(
                    nodeUrl = nodeInfo.url,  // Store the base URL
                    name = nodeInfo.name,
                    advertisedTags = response.advertisedTags,
                    status = "active",
                    lastSeen = Date(),
                    podConfigId = pod.id
                )
            }
        } catch (e: Exception) {
            Log.e("PodClient", "Error discovering nodes", e)
            e.printStackTrace()
            emptyList()
        }
    }

    suspend fun fetchDigests(
        node: PodNode,
        tags: List<String>,
        podKey: String,
        page: Int = 1,
        perPage: Int = 50,
        startDate: Date? = null,
        endDate: Date? = null
    ): DigestsResponse {
        val service = createService(node.nodeUrl)  // createService will add /api/pods/

        Log.d("PodClient", "Fetching digests from: ${node.nodeUrl}")
        Log.d("PodClient", "Tags: ${tags.joinToString(",")}")

        val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

        return service.getDigests(
            podKey = podKey,
            tags = tags.joinToString(","),
            page = page,
            perPage = perPage,
            startDate = startDate?.let { dateFormat.format(it) },
            endDate = endDate?.let { dateFormat.format(it) }
        )
    }

    /**
     * Post a digest to a pod (for reading only - actual posting goes through probe endpoint)
     */
    suspend fun postDigest(
        pod: PodConfig,
        title: String,
        content: String,
        tags: List<String>
    ): Result<PostDigestResponse> {
        val service = createService(pod.entranceNodeUrl)

        return try {
            val response = service.postDigest(
                podKey = pod.presharedKey,
                request = PostDigestRequest(
                    title = title,
                    content = content,
                    tags = tags
                )
            )
            Result.success(response)
        } catch (e: Exception) {
            e.printStackTrace()
            Result.failure(e)
        }
    }

    // Test connection method for debugging
    suspend fun testRawConnection(pod: PodConfig): String {
        return withContext(Dispatchers.IO) {
            try {
                val fullUrl = when {
                    pod.entranceNodeUrl.endsWith("/api/pods/") -> "${pod.entranceNodeUrl}advertise"
                    pod.entranceNodeUrl.endsWith("/api/pods") -> "${pod.entranceNodeUrl}/advertise"
                    pod.entranceNodeUrl.endsWith("/") -> "${pod.entranceNodeUrl}api/pods/advertise"
                    else -> "${pod.entranceNodeUrl}/api/pods/advertise"
                }

                val url = java.net.URL(fullUrl)
                val connection = url.openConnection() as java.net.HttpURLConnection

                connection.requestMethod = "POST"
                connection.setRequestProperty("X-Pod-Key", pod.presharedKey)
                connection.setRequestProperty("Content-Type", "application/json")
                connection.doOutput = true

                val jsonBody = """{"tags": [${pod.cachedTags.joinToString { "\"$it\"" }}]}"""

                connection.outputStream.use {
                    it.write(jsonBody.toByteArray())
                }

                val responseCode = connection.responseCode
                val response = if (responseCode == 200) {
                    connection.inputStream.bufferedReader().use { it.readText() }
                } else {
                    connection.errorStream?.bufferedReader()?.use { it.readText() } ?: "No error stream"
                }

                "URL: $fullUrl\n" +
                        "Response Code: $responseCode\n" +
                        "Body sent: $jsonBody\n" +
                        "Response: $response"

            } catch (e: Exception) {
                "Error: ${e.message}\n${e.stackTraceToString()}"
            }
        }
    }
}