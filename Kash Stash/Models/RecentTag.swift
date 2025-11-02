import Foundation

struct RecentTag: Codable, Identifiable, Equatable {
    let id: UUID = UUID()  // Add default value here
    var value: String
    var lastUsed: Date
    
    static let maxRecentTags = 20
}
