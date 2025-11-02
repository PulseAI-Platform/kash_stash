import Foundation

struct KashStashEndpoint: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var device: String
    var probeKey: String
    var nodeName: String
    var probeId: String
    var keepScreenshots: Bool
    
    // NEW FIELDS for config digest support
    var configDigestId: String?
    var configDigestTags: String = "agent-config"
    var configCacheMinutes: Int = 5
}
