package com.pulseai.kashstash.pods.storage

import com.pulseai.kashstash.pods.models.Digest
import com.pulseai.kashstash.pods.models.PodConfig
import com.pulseai.kashstash.pods.models.PodNode
import kotlinx.coroutines.flow.Flow
import java.util.Date

class PodRepository(private val podDao: PodDao) {

    // Pod Config operations
    fun getAllPods(): Flow<List<PodConfig>> = podDao.getAllPods()

    fun getActivePods(): Flow<List<PodConfig>> = podDao.getActivePods()

    suspend fun getPodById(podId: String): PodConfig? = podDao.getPodById(podId)

    suspend fun insertPod(pod: PodConfig) = podDao.insertPod(pod)

    suspend fun updatePod(pod: PodConfig) = podDao.updatePod(pod)

    suspend fun deletePod(pod: PodConfig) {
        podDao.deleteNodesForPod(pod.id)
        podDao.deletePod(pod)
    }

    suspend fun togglePodActive(podId: String, isActive: Boolean) {
        podDao.updatePodActiveStatus(podId, isActive)
    }

    suspend fun updateDiscoveredTags(podId: String, tags: List<String>) {
        podDao.updateDiscoveredTags(podId, tags)
    }

    suspend fun updateLastRefresh(podId: String) {
        podDao.updateLastRefresh(podId, System.currentTimeMillis())
    }

    suspend fun updateNotificationSettings(
        podId: String,
        notifyNewDigests: Boolean? = null,
        notifyReplies: Boolean? = null
    ) {
        notifyNewDigests?.let { podDao.updateNotifyNewDigests(podId, it) }
        notifyReplies?.let { podDao.updateNotifyReplies(podId, it) }
    }

    // Pod Node operations
    suspend fun getNodesForPod(podId: String): List<PodNode> =
        podDao.getNodesForPod(podId)

    suspend fun updateNodesForPod(podId: String, nodes: List<PodNode>) {
        podDao.deleteNodesForPod(podId)
        podDao.insertNodes(nodes)
    }

    // Digest operations
    fun getRecentDigests(limit: Int = 100): Flow<List<Digest>> =
        podDao.getRecentDigests(limit)

    suspend fun getDigestById(digestId: String): Digest? =
        podDao.getDigestById(digestId)

    suspend fun insertDigests(digests: List<Digest>) =
        podDao.insertDigests(digests)

    suspend fun insertDigest(digest: Digest) =
        podDao.insertDigest(digest)

    fun getRepliesToMe(): Flow<List<Digest>> =
        podDao.getRepliesToMe()

    fun getMyPosts(): Flow<List<Digest>> =
        podDao.getMyPosts()

    fun searchDigests(query: String): Flow<List<Digest>> =
        podDao.searchDigests(query)

    // Cleanup operations
    suspend fun cleanupOldDigests(daysToKeep: Int = 30) {
        val cutoffTime = System.currentTimeMillis() - (daysToKeep * 24 * 60 * 60 * 1000L)
        podDao.deleteOldDigests(cutoffTime)
    }

    suspend fun clearAllData() {
        podDao.deleteAllDigests()
        podDao.deleteAllNodes()
        podDao.deleteAllPods()
    }
}