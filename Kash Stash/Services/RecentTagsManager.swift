import Foundation

class RecentTagsManager {
    static func addTags(_ tagsString: String, to config: inout AppConfig) {
        let tags = tagsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let now = Date()
        
        for tag in tags {
            // Remove if already exists
            config.recentTags.removeAll { $0.value.lowercased() == tag.lowercased() }
            // Add at front
            config.recentTags.insert(RecentTag(value: tag, lastUsed: now), at: 0)
        }
        
        // Keep only most recent
        if config.recentTags.count > RecentTag.maxRecentTags {
            config.recentTags = Array(config.recentTags.prefix(RecentTag.maxRecentTags))
        }
    }
    
    static func getRecentTagsString(from config: AppConfig, limit: Int = 10) -> [String] {
        Array(config.recentTags.prefix(limit)).map { $0.value }
    }
}
