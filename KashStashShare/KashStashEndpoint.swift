import Foundation

struct KashStashEndpoint: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var device: String
    var probeKey: String
    var nodeName: String
    var probeId: String
    var keepScreenshots: Bool
    
    var configDigestId: String?
    var configDigestTags: String = "agent-config"
    var configCacheMinutes: Int = 5
}

struct KashFilesConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var key: String
    var isActive: Bool = false
    
    var baseURL: String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }
}

enum UploadDestination: String, Codable, CaseIterable {
    case endpointOnly = "Endpoint Only"
    case kashFilesOnly = "Kash Files Only"
    case both = "Both"
}

struct AppConfig: Codable, Equatable {
    var endpoints: [KashStashEndpoint]
    var lastUsedEndpoint: UUID?
    
    var kashFiles: [KashFilesConfig] = []
    var lastUsedKashFilesId: UUID?
    var recentTags: [RecentTag] = []
    var recentPrompts: [RecentPrompt] = []
    var defaultUploadDestination: UploadDestination = .endpointOnly
    
    var podConfigs: [PodConfig] = []
    var lastUsedPodId: UUID?
    var deviceName: String = ""
    
    var configVersion: Int = 3
}
