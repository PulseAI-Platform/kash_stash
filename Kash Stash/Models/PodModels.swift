// Models/PodModels.swift
import Foundation

// In PodModels.swift, update PodConfig:
struct PodConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var entranceNodeUrl: String
    var presharedKey: String
    var isActive: Bool
    var lastRefresh: Date?
    var discoveredNodes: [PodNode]
    var cachedTags: [String]  // Advertised tags
    var discoveredTags: [String] = []  // Tags found in actual digests
    
    // Notification preferences
    var notifyNewDigests: Bool = false
    var notifyReplies: Bool = false
    var lastSeenDigestId: String? = nil
    var lastSeenReplyId: String? = nil
    
    // Computed properties for Set operations
    var cachedTagsSet: Set<String> {
        get { Set(cachedTags) }
        set { cachedTags = Array(newValue) }
    }
    
    var discoveredTagsSet: Set<String> {
        get { Set(discoveredTags) }
        set { discoveredTags = Array(newValue) }
    }
    
    // All available tags (advertised + discovered)
    var allTags: [String] {
        Array(Set(cachedTags + discoveredTags)).sorted()
    }
    
    var allTagsSet: Set<String> {
        Set(cachedTags + discoveredTags)
    }
    
    init(id: UUID = UUID(),
         name: String,
         entranceNodeUrl: String,
         presharedKey: String,
         isActive: Bool = true,
         lastRefresh: Date? = nil,
         discoveredNodes: [PodNode] = [],
         cachedTags: [String] = [],
         discoveredTags: [String] = [],
         notifyNewDigests: Bool = false,
         notifyReplies: Bool = false,
         lastSeenDigestId: String? = nil,
         lastSeenReplyId: String? = nil) {
        self.id = id
        self.name = name
        self.entranceNodeUrl = entranceNodeUrl
        self.presharedKey = presharedKey
        self.isActive = isActive
        self.lastRefresh = lastRefresh
        self.discoveredNodes = discoveredNodes
        self.cachedTags = cachedTags
        self.discoveredTags = discoveredTags
        self.notifyNewDigests = notifyNewDigests
        self.notifyReplies = notifyReplies
        self.lastSeenDigestId = lastSeenDigestId
        self.lastSeenReplyId = lastSeenReplyId
    }
}

struct PodNode: Codable, Identifiable, Equatable {
    let id: UUID
    var nodeUrl: String
    var name: String
    var advertisedTags: [String]
    var status: String
    var lastSeen: Date?
    // Notification preferences
    var notifyNewDigests: Bool = false
    var notifyReplies: Bool = false
    var lastSeenDigestId: String? = nil
    var lastSeenReplyId: String? = nil
    
    init(id: UUID = UUID(),
         nodeUrl: String,
         name: String,
         advertisedTags: [String] = [],
         status: String = "unknown",
         lastSeen: Date? = nil) {
        self.id = id
        self.nodeUrl = nodeUrl
        self.name = name
        self.advertisedTags = advertisedTags
        self.status = status
        self.lastSeen = lastSeen
    }
}

struct Digest: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var content: String
    var tags: [String]
    var sourceNode: String?
    var createdAt: Date
    var inPods: [String]
    var isMyPost: Bool
    var isReplyToMe: Bool
    var repliesTo: String?
    var replyToDevice: String?  // Add this
    
    // Computed properties for reply detection
    var isReply: Bool {
        content.contains("@[") || content.contains("@reply:")
    }
    
    // Parse reply metadata from content
    // In Digest model, update parseReplyInfo:

    func parseReplyInfo(myDeviceName: String, myNodeName: String) -> (isReplyToMe: Bool, replyToDevice: String?) {
        // Check for new format: @podname.probes-node-name.xyzpulseinfra.com.digestid.devicename
        if let atIndex = content.firstIndex(of: "@") {
            let afterAt = content[content.index(after: atIndex)...]
            
            // Find the end of the mention (space or newline)
            let endIndex = afterAt.firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? afterAt.endIndex
            let mention = String(afterAt[..<endIndex])
            
            // Split by dots to get components
            let components = mention.split(separator: ".")
            
            // Check if it has enough components and matches our device
            if components.count >= 5 {
                let targetDevice = String(components.last ?? "")
                let isToMe = targetDevice.lowercased() == myDeviceName.lowercased().replacingOccurrences(of: " ", with: "-")
                return (isToMe, targetDevice)
            }
        }
        
        // Fallback: check tags for device mentions
        let deviceTag = myDeviceName.lowercased().replacingOccurrences(of: " ", with: "-")
        if tags.contains(deviceTag) && content.contains("@") {
            return (true, nil)
        }
        
        return (false, nil)
    }
    
    // Computed property for Set operations
    var inPodsSet: Set<String> {
        get { Set(inPods) }
        set { inPods = Array(newValue) }
    }
    
    init(id: String,
         title: String,
         content: String,
         tags: [String] = [],
         sourceNode: String? = nil,
         createdAt: Date,
         inPods: [String] = [],
         isMyPost: Bool = false,
         isReplyToMe: Bool = false,
         repliesTo: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.tags = tags
        self.sourceNode = sourceNode
        self.createdAt = createdAt
        self.inPods = inPods
        self.isMyPost = isMyPost
        self.isReplyToMe = isReplyToMe
        self.repliesTo = repliesTo
    }
}

// Response structures from the API
struct AdvertiseResponse: Codable {
    let nodeName: String
    let advertisedTags: [String]
    let nodes: [NodeInfo]
    
    struct NodeInfo: Codable {
        let url: String
        let name: String
    }
    
    private enum CodingKeys: String, CodingKey {
        case nodeName = "node_name"
        case advertisedTags = "advertised_tags"
        case nodes
    }
}

// In PodModels.swift, update the DigestsResponse structures:

// In PodModels.swift, make sure the DigestEntry has correct mapping:
struct DigestsResponse: Codable {
    let feedentries: [DigestEntry]
    let total: Int
    let page: Int
    let pages: Int
    
    struct DigestEntry: Codable {
        let id: Int
        let title: String?
        let content: String?
        let tags: [Tag]?
        let sourceNode: String?
        let createdAt: String? // This should map to created_at from API
        
        struct Tag: Codable {
            let id: Int
            let name: String
            let created: String
        }
        
        private enum CodingKeys: String, CodingKey {
            case id, title, content, tags
            case sourceNode = "source_node"
            case createdAt = "created"  // MUST be created_at not created
        }
    }
}

// Update the Digest extension to handle the new format:
extension Digest {
    init(from entry: DigestsResponse.DigestEntry) {
        self.id = String(entry.id)  // Convert Int to String
        self.title = entry.title ?? ""
        self.content = entry.content ?? ""
        
        // Extract tag names from tag objects
        self.tags = entry.tags?.map { $0.name } ?? []
        
        self.sourceNode = entry.sourceNode
        
        // Parse date from string
        if let dateStr = entry.createdAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.createdAt = formatter.date(from: dateStr) ?? Date()
        } else {
            self.createdAt = Date()
        }
        
        self.inPods = []
        self.isMyPost = false
        self.isReplyToMe = false
        self.repliesTo = nil
    }
}
