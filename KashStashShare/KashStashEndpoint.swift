import Foundation

struct KashStashEndpoint: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var device: String
    var probeKey: String
    var nodeName: String
    var probeId: String
    var keepScreenshots: Bool
}

// THIS IS WHAT YOU'RE MISSING:
struct AppConfig: Codable, Equatable {
    var endpoints: [KashStashEndpoint]
    var lastUsedEndpoint: UUID?
}
