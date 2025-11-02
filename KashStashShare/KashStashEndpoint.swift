import Foundation

// Copy all the shared models here
struct KashStashEndpoint: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var device: String
    var probeKey: String
    var nodeName: String
    var probeId: String
    var keepScreenshots: Bool
    
    // NEW FIELDS for config digest support (not used in share extension)
    var configDigestId: String?
    var configDigestTags: String = "agent-config"
    var configCacheMinutes: Int = 5
}

struct KashFilesConfig: Codable, Identifiable, Equatable {
    let id = UUID()
    var name: String
    var url: String
    var key: String
    var isActive: Bool = false
    
    var baseURL: String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }
}

struct RecentTag: Codable, Identifiable, Equatable {
    let id: UUID = UUID()
    var value: String
    var lastUsed: Date
    
    static let maxRecentTags = 20
}

enum UploadDestination: String, Codable, CaseIterable {
    case endpointOnly = "Endpoint Only"
    case kashFilesOnly = "Kash Files Only"
    case both = "Both"
}

struct AppConfig: Codable, Equatable {
    var endpoints: [KashStashEndpoint]
    var lastUsedEndpoint: UUID?
    
    // NEW FIELDS
    var kashFiles: [KashFilesConfig] = []
    var lastUsedKashFilesId: UUID?
    var recentTags: [RecentTag] = []
    var defaultUploadDestination: UploadDestination = .endpointOnly
    
    // Migration support
    var configVersion: Int = 2
}
