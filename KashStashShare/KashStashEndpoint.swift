import Foundation

// MARK: - Share Extension Models
// RecentTag, RecentPrompt, PodConfig, PodNode are shared from main app via target membership

struct KashStashEndpoint: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var device: String
    var probeKey: String
    var nodeName: String
    var probeId: String
    
    // Properties added to match Main App and prevent data loss during save
    var keepScreenshots: Bool
    var configDigestId: String?
    var configDigestTags: String = "agent-config"
    var configCacheMinutes: Int = 5
    
    // Fallback init for decoding if fields are missing from an older/corrupt file
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        device = try container.decode(String.self, forKey: .device)
        probeKey = try container.decode(String.self, forKey: .probeKey)
        nodeName = try container.decode(String.self, forKey: .nodeName)
        probeId = try container.decode(String.self, forKey: .probeId)
        
        // Use defaults if keys are missing to gracefully recover
        keepScreenshots = try container.decodeIfPresent(Bool.self, forKey: .keepScreenshots) ?? false
        configDigestId = try container.decodeIfPresent(String.self, forKey: .configDigestId)
        configDigestTags = try container.decodeIfPresent(String.self, forKey: .configDigestTags) ?? "agent-config"
        configCacheMinutes = try container.decodeIfPresent(Int.self, forKey: .configCacheMinutes) ?? 5
    }
}

struct KashFilesConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var url: String
    var key: String
    var isActive: Bool
    
    var baseURL: String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }
}

enum UploadDestination: String, Codable, CaseIterable {
    case endpointOnly = "Endpoint Only"
    case kashFilesOnly = "Kash Files Only"
    case linkAndCaption = "Link + Caption"
    case both = "Both"
    
    var displayName: String {
        return self.rawValue
    }
}

struct AppConfig: Codable {
    var endpoints: [KashStashEndpoint]
    var lastUsedEndpoint: UUID?
    var kashFiles: [KashFilesConfig]
    var lastUsedKashFilesId: UUID?
    var recentTags: [RecentTag]
    var recentPrompts: [RecentPrompt]
    var defaultUploadDestination: UploadDestination
    var podConfigs: [PodConfig]
    var lastUsedPodId: UUID?
    var deviceName: String
    var configVersion: Int
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        endpoints = try container.decodeIfPresent([KashStashEndpoint].self, forKey: .endpoints) ?? []
        lastUsedEndpoint = try container.decodeIfPresent(UUID.self, forKey: .lastUsedEndpoint)
        kashFiles = try container.decodeIfPresent([KashFilesConfig].self, forKey: .kashFiles) ?? []
        lastUsedKashFilesId = try container.decodeIfPresent(UUID.self, forKey: .lastUsedKashFilesId)
        recentTags = try container.decodeIfPresent([RecentTag].self, forKey: .recentTags) ?? []
        recentPrompts = try container.decodeIfPresent([RecentPrompt].self, forKey: .recentPrompts) ?? []
        defaultUploadDestination = try container.decodeIfPresent(UploadDestination.self, forKey: .defaultUploadDestination) ?? .endpointOnly
        podConfigs = try container.decodeIfPresent([PodConfig].self, forKey: .podConfigs) ?? []
        lastUsedPodId = try container.decodeIfPresent(UUID.self, forKey: .lastUsedPodId)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? ""
        configVersion = try container.decodeIfPresent(Int.self, forKey: .configVersion) ?? 3
    }
    
    // Explicit init used when creating new configs or defaults
    init(
        endpoints: [KashStashEndpoint] = [],
        lastUsedEndpoint: UUID? = nil,
        kashFiles: [KashFilesConfig] = [],
        lastUsedKashFilesId: UUID? = nil,
        recentTags: [RecentTag] = [],
        recentPrompts: [RecentPrompt] = [],
        defaultUploadDestination: UploadDestination = .endpointOnly,
        podConfigs: [PodConfig] = [],
        lastUsedPodId: UUID? = nil,
        deviceName: String = "",
        configVersion: Int = 3
    ) {
        self.endpoints = endpoints
        self.lastUsedEndpoint = lastUsedEndpoint
        self.kashFiles = kashFiles
        self.lastUsedKashFilesId = lastUsedKashFilesId
        self.recentTags = recentTags
        self.recentPrompts = recentPrompts
        self.defaultUploadDestination = defaultUploadDestination
        self.podConfigs = podConfigs
        self.lastUsedPodId = lastUsedPodId
        self.deviceName = deviceName
        self.configVersion = configVersion
    }
}