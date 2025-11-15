package com.pulseai.kashstash.pods.storage

import androidx.room.*
import com.pulseai.kashstash.pods.models.Digest
import com.pulseai.kashstash.pods.models.PodConfig
import com.pulseai.kashstash.pods.models.PodNode
import kotlinx.coroutines.flow.Flow

@Dao
interface PodDao {
    // Pod Config operations
    @Query("SELECT * FROM pod_configs ORDER BY name ASC")
    fun getAllPods(): Flow<List<PodConfig>>

    @Query("SELECT * FROM pod_configs WHERE isActive = 1")
    fun getActivePods(): Flow<List<PodConfig>>

    @Query("SELECT * FROM pod_configs WHERE id = :podId")
    suspend fun getPodById(podId: String): PodConfig?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPod(pod: PodConfig)

    @Update
    suspend fun updatePod(pod: PodConfig)

    @Delete
    suspend fun deletePod(pod: PodConfig)

    @Query("UPDATE pod_configs SET isActive = :isActive WHERE id = :podId")
    suspend fun updatePodActiveStatus(podId: String, isActive: Boolean)

    @Query("UPDATE pod_configs SET discoveredTags = :tags WHERE id = :podId")
    suspend fun updateDiscoveredTags(podId: String, tags: List<String>)

    @Query("UPDATE pod_configs SET lastRefresh = :timestamp WHERE id = :podId")
    suspend fun updateLastRefresh(podId: String, timestamp: Long)

    @Query("UPDATE pod_configs SET notifyNewDigests = :notify WHERE id = :podId")
    suspend fun updateNotifyNewDigests(podId: String, notify: Boolean)

    @Query("UPDATE pod_configs SET notifyReplies = :notify WHERE id = :podId")
    suspend fun updateNotifyReplies(podId: String, notify: Boolean)

    // Pod Node operations
    @Query("SELECT * FROM pod_nodes WHERE podConfigId = :podId")
    suspend fun getNodesForPod(podId: String): List<PodNode>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertNodes(nodes: List<PodNode>)

    @Query("DELETE FROM pod_nodes WHERE podConfigId = :podId")
    suspend fun deleteNodesForPod(podId: String)

    // Digest operations
    @Query("SELECT * FROM digests ORDER BY createdAt DESC LIMIT :limit")
    fun getRecentDigests(limit: Int = 100): Flow<List<Digest>>

    @Query("SELECT * FROM digests WHERE id = :digestId")
    suspend fun getDigestById(digestId: String): Digest?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertDigests(digests: List<Digest>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertDigest(digest: Digest)

    @Query("DELETE FROM digests WHERE createdAt < :timestamp")
    suspend fun deleteOldDigests(timestamp: Long)

    @Query("SELECT * FROM digests WHERE isReplyToMe = 1 ORDER BY createdAt DESC")
    fun getRepliesToMe(): Flow<List<Digest>>

    @Query("SELECT * FROM digests WHERE isMyPost = 1 ORDER BY createdAt DESC")
    fun getMyPosts(): Flow<List<Digest>>

    // Search and filter
    @Query("""
        SELECT * FROM digests 
        WHERE content LIKE '%' || :query || '%' 
        OR title LIKE '%' || :query || '%'
        ORDER BY createdAt DESC
    """)
    fun searchDigests(query: String): Flow<List<Digest>>

    // Clear all data
    @Query("DELETE FROM pod_configs")
    suspend fun deleteAllPods()

    @Query("DELETE FROM pod_nodes")
    suspend fun deleteAllNodes()

    @Query("DELETE FROM digests")
    suspend fun deleteAllDigests()
}