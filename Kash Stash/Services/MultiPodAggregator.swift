// Services/MultiPodAggregator.swift
import Foundation

class MultiPodAggregator {
    private let podClient: PodClient
    private let replyDetector: DigestReplyDetector
    
    init(podClient: PodClient, deviceName: String) {
        self.podClient = podClient
        self.replyDetector = DigestReplyDetector(deviceName: deviceName)
    }
    
    func fetchFromAllPods(
        pods: [PodConfig],
        startDate: Date? = nil,
        endDate: Date? = nil,
        tags: Set<String>? = nil
    ) async throws -> [Digest] {
        var allDigests: [String: Digest] = [:] // Use dict to dedupe by ID
        
        // Fetch from all pods in parallel
        await withTaskGroup(of: (String, [Digest]).self) { group in
            for pod in pods where pod.isActive {
                group.addTask {
                    do {
                        let digests = try await self.fetchFromPod(
                            pod: pod,
                            startDate: startDate,
                            endDate: endDate,
                            tags: tags
                        )
                        return (pod.name, digests)
                    } catch {
                        print("Failed to fetch from pod \(pod.name): \(error)")
                        return (pod.name, [])
                    }
                }
            }
            
            // Collect results and mark which pods each digest appears in
            for await (podName, digests) in group {
                for digest in digests {
                    if var existing = allDigests[digest.id] {
                        existing.inPods.append(podName)
                        allDigests[digest.id] = existing
                    } else {
                        var newDigest = digest
                        newDigest.inPods = [podName]
                        allDigests[digest.id] = newDigest
                    }
                }
            }
        }
        
        // Analyze for replies to user's posts
        let analyzed = replyDetector.analyzeDigests(Array(allDigests.values))
        
        // Sort by date, newest first
        return analyzed.sorted { $0.createdAt > $1.createdAt }
    }
    
    // In MultiPodAggregator.swift, update the fetchFromPod method:
    private func fetchFromPod(
        pod: PodConfig,
        startDate: Date?,
        endDate: Date?,
        tags: Set<String>?
    ) async throws -> [Digest] {
        var allDigests: [Digest] = []
        var discoveredTags = Set<String>()  // Track all tags we find
        
        // Ensure we have discovered nodes
        var nodes = pod.discoveredNodes
        if nodes.isEmpty {
            nodes = try await podClient.discoverNodes(pod: pod)
        }
        
        // Determine which tags to fetch
        let tagsToFetch: [String]
        if let requestedTags = tags {
            // Intersection of requested tags and pod's advertised tags
            tagsToFetch = Array(requestedTags.intersection(pod.cachedTagsSet))
        } else {
            // Fetch all advertised tags
            tagsToFetch = pod.cachedTags
        }
        
        guard !tagsToFetch.isEmpty else {
            return []
        }
        
        // Fetch from each node in parallel
        await withTaskGroup(of: ([Digest], Set<String>).self) { group in
            for node in nodes where node.status == "active" {
                group.addTask {
                    do {
                        let response = try await self.podClient.fetchDigests(
                            from: node,
                            tags: tagsToFetch,
                            podKey: pod.presharedKey,
                            page: 1,
                            perPage: 50,
                            startDate: startDate,
                            endDate: endDate
                        )
                        
                        // Convert response entries to Digest objects
                        let digests = response.feedentries.map { entry in
                            Digest(from: entry)
                        }
                        
                        // Collect all tags from the digests
                        let tagsInDigests = Set(digests.flatMap { $0.tags })
                        
                        return (digests, tagsInDigests)
                    } catch {
                        print("Failed to fetch from node \(node.name): \(error)")
                        return ([], Set<String>())
                    }
                }
            }
            
            // Collect all digests and tags
            for await (nodeDigests, nodeTags) in group {
                allDigests.append(contentsOf: nodeDigests)
                discoveredTags.formUnion(nodeTags)
            }
        }
        
        // Update the pod's discovered tags
        if !discoveredTags.isEmpty {
            AppConfigStore.updateDiscoveredTags(podId: pod.id, tags: Array(discoveredTags))
        }
        
        // Dedupe by ID (in case multiple nodes have the same digest)
        var seen = Set<String>()
        return allDigests.filter { digest in
            if seen.contains(digest.id) {
                return false
            }
            seen.insert(digest.id)
            return true
        }
    }
}
