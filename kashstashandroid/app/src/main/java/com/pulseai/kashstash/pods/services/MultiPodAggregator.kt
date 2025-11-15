package com.pulseai.kashstash.pods.services

import com.pulseai.kashstash.pods.models.Digest
import com.pulseai.kashstash.pods.models.PodConfig
import com.pulseai.kashstash.pods.models.PodNode
import com.pulseai.kashstash.pods.models.toDigest
import com.pulseai.kashstash.pods.storage.PodRepository
import kotlinx.coroutines.*
import java.util.Date
import android.util.Log


class MultiPodAggregator(
    private val podClient: PodClient,
    private val repository: PodRepository,
    private val deviceNames: Set<String>
) {
    private val replyDetector = DigestReplyDetector(deviceNames)

    /**
     * Fetch digests from all active pods
     */
    suspend fun fetchFromAllPods(
        pods: List<PodConfig>,
        startDate: Date? = null,
        endDate: Date? = null,
        tags: Set<String>? = null
    ): List<Digest> = withContext(Dispatchers.IO) {
        val allDigests = mutableMapOf<String, Digest>()

        // Fetch from all pods in parallel
        val results = pods.filter { it.isActive }.map { pod ->
            async {
                try {
                    val digests = fetchFromPod(pod, startDate, endDate, tags)
                    pod.name to digests  // Return pod name with digests
                } catch (e: Exception) {
                    e.printStackTrace()
                    pod.name to emptyList<Digest>()
                }
            }
        }.awaitAll()

        // Collect results and mark which pods each digest appears in
        results.forEach { (podName, digests) ->
            for (digest in digests) {
                if (allDigests.containsKey(digest.id)) {
                    val existing = allDigests[digest.id]!!
                    allDigests[digest.id] = existing.copy(
                        inPods = existing.inPods + podName
                    )
                } else {
                    allDigests[digest.id] = digest.copy(inPods = listOf(podName))
                }
            }
        }

        // Analyze for replies with device names
        val analyzed = replyDetector.analyzeDigests(allDigests.values.toList())

        Log.d("MultiPodAggregator", "Analyzed ${analyzed.size} digests. My posts: ${analyzed.count { it.isMyPost }}, Replies to me: ${analyzed.count { it.isReplyToMe }}")

        // Sort by date, newest first
        analyzed.sortedByDescending { it.createdAt }
    }

    /**
     * Helper method to fetch all pages for a tag
     */
    private suspend fun fetchAllPagesForTag(
        node: PodNode,
        tag: String,
        podKey: String,
        startDate: Date?,
        endDate: Date?
    ): List<FeedEntry> {
        val allEntries = mutableListOf<FeedEntry>()
        var currentPage = 1
        var totalPages = 1

        do {
            try {
                val response = podClient.fetchDigests(
                    node = node,
                    tags = listOf(tag),
                    podKey = podKey,
                    page = currentPage,
                    perPage = 100,
                    startDate = startDate,
                    endDate = endDate
                )

                allEntries.addAll(response.feedentries)
                totalPages = response.pages

                Log.d("MultiPodAggregator", "Tag '$tag' - fetched page $currentPage/$totalPages (${response.feedentries.size} entries)")

                currentPage++

            } catch (e: Exception) {
                Log.e("MultiPodAggregator", "Error fetching page $currentPage for tag '$tag'", e)
                break
            }
        } while (currentPage <= totalPages && currentPage <= 10) // Limit to 5 pages max

        Log.d("MultiPodAggregator", "Tag '$tag' - total fetched: ${allEntries.size} entries")
        return allEntries
    }

    /**
     * Fetch digests from a single pod
     */
    private suspend fun fetchFromPod(
        pod: PodConfig,
        startDate: Date?,
        endDate: Date?,
        tags: Set<String>?
    ): List<Digest> = withContext(Dispatchers.IO) {
        val discoveredTagsSet = mutableSetOf<String>()

        // Get or discover nodes
        var nodes = repository.getNodesForPod(pod.id)
        if (nodes.isEmpty()) {
            Log.d("MultiPodAggregator", "No nodes in DB for pod ${pod.name}, discovering...")
            try {
                nodes = podClient.discoverNodes(pod)
                Log.d("MultiPodAggregator", "Discovery returned ${nodes.size} nodes")

                if (nodes.isNotEmpty()) {
                    val nodesWithPodId = nodes.map { it.copy(podConfigId = pod.id) }
                    repository.updateNodesForPod(pod.id, nodesWithPodId)
                    nodes = nodesWithPodId

                    if (nodes.isNotEmpty() && nodes[0].advertisedTags.isNotEmpty()) {
                        repository.updateDiscoveredTags(pod.id, nodes[0].advertisedTags)
                    }

                    Log.d("MultiPodAggregator", "Saved ${nodes.size} nodes to DB")
                } else {
                    Log.e("MultiPodAggregator", "No nodes discovered for pod ${pod.name}")
                    return@withContext emptyList()
                }
            } catch (e: Exception) {
                Log.e("MultiPodAggregator", "Error discovering nodes", e)
                return@withContext emptyList()
            }
        }

        // Use the advertised tags from the nodes
        val availableTags = nodes.firstOrNull()?.advertisedTags ?: emptyList()

        val tagsToFetch = when {
            tags != null && tags.isNotEmpty() ->
                tags.intersect(availableTags.toSet()).toList()
            availableTags.isNotEmpty() ->
                availableTags
            else -> {
                Log.w("MultiPodAggregator", "No tags available from nodes")
                return@withContext emptyList()
            }
        }

        if (tagsToFetch.isEmpty()) {
            Log.w("MultiPodAggregator", "No valid tags to fetch")
            return@withContext emptyList()
        }

        Log.d("MultiPodAggregator", "Will fetch tags: ${tagsToFetch.joinToString(",")}")

        // Fetch from each active node
        val allDigests = mutableMapOf<String, Digest>()  // Use map for deduplication

        nodes.filter { it.status == "active" }.forEach { node ->
            // PARALLEL TAG FETCHING - Create async jobs for each tag
            val tagJobs = tagsToFetch.map { tag ->
                async {
                    try {
                        Log.d("MultiPodAggregator", "Starting parallel fetch for tag '$tag' from node: ${node.name}")

                        val entries = fetchAllPagesForTag(
                            node = node,
                            tag = tag,
                            podKey = pod.presharedKey,
                            startDate = startDate,
                            endDate = endDate
                        )

                        Log.d("MultiPodAggregator", "Completed fetch for tag '$tag': ${entries.size} entries")
                        entries
                    } catch (e: Exception) {
                        Log.e("MultiPodAggregator", "Failed to fetch tag '$tag' from node ${node.name}", e)
                        emptyList<FeedEntry>()
                    }
                }
            }

            // Wait for all tag fetches to complete and process results
            val allTagResults = tagJobs.awaitAll()

            // Process all results together with proper synchronization
            synchronized(allDigests) {
                allTagResults.flatten().forEach { entry ->
                    val digest = entry.toDigest()
                    // Only add if we haven't seen this ID yet
                    if (!allDigests.containsKey(digest.id)) {
                        allDigests[digest.id] = digest
                    }
                    discoveredTagsSet.addAll(digest.tags)
                }
            }

            Log.d("MultiPodAggregator", "Node ${node.name} complete. Total unique digests: ${allDigests.size}")
        }

        // Update discovered tags
        if (discoveredTagsSet.isNotEmpty()) {
            repository.updateDiscoveredTags(pod.id, discoveredTagsSet.toList())
        }

        // Update last refresh
        repository.updateLastRefresh(pod.id)

        Log.d("MultiPodAggregator", "Returning ${allDigests.size} deduplicated digests for pod ${pod.name}")

        // Return deduplicated digests
        allDigests.values.toList()
    }

    /**
     * Refresh a single pod
     */
    suspend fun refreshPod(pod: PodConfig): List<Digest> {
        return fetchFromPod(pod, null, null, null)
    }

    /**
     * Fetch nodes for a specific pod
     */
    suspend fun fetchNodesForPod(pod: PodConfig): List<PodNode> {
        return try {
            podClient.discoverNodes(pod)
        } catch (e: Exception) {
            emptyList()
        }
    }
}
