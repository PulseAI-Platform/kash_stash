import Foundation

struct RecentPrompt: Codable, Identifiable, Equatable {
    let id: UUID = UUID()
    var value: String
    var lastUsed: Date
    
    static let maxRecentPrompts = 20
}