package com.pulseai.kashstash.pods.services

import com.pulseai.kashstash.pods.models.AdvertiseResponse
import retrofit2.http.*
import com.google.gson.annotations.SerializedName

interface PodApiService {

    @GET("advertise")
    suspend fun advertise(
        @Header("X-Pod-Key") podKey: String
    ): AdvertiseResponse

    @GET("digests")
    suspend fun getDigests(
        @Header("X-Pod-Key") podKey: String,
        @Query("tags") tags: String,
        @Query("page") page: Int = 1,
        @Query("per_page") perPage: Int = 50,
        @Query("start_date") startDate: String? = null,
        @Query("end_date") endDate: String? = null
    ): DigestsResponse

    @POST("digests")
    suspend fun postDigest(
        @Header("X-Pod-Key") podKey: String,
        @Body request: PostDigestRequest
    ): PostDigestResponse
}

data class PostDigestRequest(
    val title: String,
    val content: String,
    val tags: List<String>
)

data class PostDigestResponse(
    val id: Int,
    val title: String,
    val content: String,
    val tags: List<String>,
    val created: String
)

// FIX: Update these models to match the actual response
data class DigestsResponse(
    @SerializedName("feedentries")
    val feedentries: List<FeedEntry>,
    val total: Int,
    val page: Int,
    val pages: Int
)

data class FeedEntry(
    val id: Int,  // Changed from String to Int
    val content: String,
    val tags: List<TagInfo>,  // Changed from List<String> to List<TagInfo>
    @SerializedName("source_node")
    val sourceNode: String? = null,
    @SerializedName("created")
    val created: String
)

data class TagInfo(
    val id: Int,
    val name: String,
    val created: String
)