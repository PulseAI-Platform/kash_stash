import Foundation

class RecentPromptsManager {
    static func addPrompt(_ prompt: String, to config: inout AppConfig) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        
        let now = Date()
        
        // Remove if already exists (case-insensitive)
        config.recentPrompts.removeAll { $0.value.lowercased() == cleanPrompt.lowercased() }
        
        // Add at front
        config.recentPrompts.insert(RecentPrompt(value: cleanPrompt, lastUsed: now), at: 0)
        
        // Keep only most recent
        if config.recentPrompts.count > RecentPrompt.maxRecentPrompts {
            config.recentPrompts = Array(config.recentPrompts.prefix(RecentPrompt.maxRecentPrompts))
        }
    }
    
    static func getRecentPromptsString(from config: AppConfig, limit: Int = 10) -> [String] {
        Array(config.recentPrompts.prefix(limit)).map { $0.value }
    }
    
    static func deletePrompt(_ prompt: String, from config: inout AppConfig) {
        config.recentPrompts.removeAll { $0.value == prompt }
    }
}