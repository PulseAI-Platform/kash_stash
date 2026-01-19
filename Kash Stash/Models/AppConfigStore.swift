import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AppConfig: Codable, Equatable {
    var endpoints: [KashStashEndpoint]
    var lastUsedEndpoint: UUID?
    
    var kashFiles: [KashFilesConfig] = []
    var lastUsedKashFilesId: UUID?
    var recentTags: [RecentTag] = []
    var recentPrompts: [RecentPrompt] = []
    var defaultUploadDestination: UploadDestination = .endpointOnly
    
    // New pod-related fields
    var podConfigs: [PodConfig] = []
    var lastUsedPodId: UUID?
    var deviceName: String = ""
    
    var configVersion: Int = 3  // Bumped from 2 to 3 for pods
}

enum UploadDestination: String, Codable, CaseIterable {
    case endpointOnly = "Endpoint Only"
    case kashFilesOnly = "Kash Files Only"
    case linkAndCaption = "Link + Caption"
    case both = "Both"
}

class AppConfigStore {
    static let filename = "kash_stash_config.json"

    static var configURL: URL {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.pulseai.kashstash")!
            .appendingPathComponent(filename)
    }

    @discardableResult
    static func save(_ config: AppConfig) -> Bool {
        do {
            // Create a backup first
            if let existingData = try? Data(contentsOf: configURL) {
                let backupURL = configURL.appendingPathExtension("backup")
                try? existingData.write(to: backupURL)
            }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted // Makes it easier to debug
            let data = try encoder.encode(config)
            try data.write(to: configURL)
            
            print("[AppConfigStore] Successfully saved config with \(config.endpoints.count) endpoints, \(config.kashFiles.count) KashFiles, and \(config.podConfigs.count) pods")
            return true
        } catch {
            print("[AppConfigStore] SAVE ERROR: \(error)")
            print("[AppConfigStore] Failed config had \(config.endpoints.count) endpoints, \(config.kashFiles.count) KashFiles, and \(config.podConfigs.count) pods")
            return false
        }
    }

    static func load() -> AppConfig {
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            var config = try decoder.decode(AppConfig.self, from: data)
            
            // Migrate old configs
            if config.configVersion < 3 {
                config = migrateConfig(config)
            }
            
            print("[AppConfigStore] Successfully loaded config with \(config.endpoints.count) endpoints, \(config.kashFiles.count) KashFiles, and \(config.podConfigs.count) pods")
            return config
        } catch DecodingError.keyNotFound(let key, let context) {
            print("[AppConfigStore] Decoding error - missing key: \(key.stringValue)")
            print("[AppConfigStore] Context: \(context)")
            
            // Try to load backup
            if let backup = loadBackup() {
                print("[AppConfigStore] Loaded from backup")
                return backup
            }
        } catch DecodingError.typeMismatch(let type, let context) {
            print("[AppConfigStore] Decoding error - type mismatch: \(type)")
            print("[AppConfigStore] Context: \(context)")
            
            // Try to load backup
            if let backup = loadBackup() {
                print("[AppConfigStore] Loaded from backup")
                return backup
            }
        } catch {
            print("[AppConfigStore] Load error: \(error)")
            
            // Try to load backup
            if let backup = loadBackup() {
                print("[AppConfigStore] Loaded from backup")
                return backup
            }
        }
        
        // Only return empty config if we have no other option
        print("[AppConfigStore] WARNING: Returning empty default config - all data will be lost!")
        return AppConfig(endpoints: [], lastUsedEndpoint: nil)
    }
    
    private static func loadBackup() -> AppConfig? {
        let backupURL = configURL.appendingPathExtension("backup")
        
        guard let data = try? Data(contentsOf: backupURL) else {
            print("[AppConfigStore] No backup file found")
            return nil
        }
        
        do {
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            print("[AppConfigStore] Successfully loaded backup with \(config.endpoints.count) endpoints, \(config.kashFiles.count) KashFiles, and \(config.podConfigs.count) pods")
            
            // Save it as the main config
            _ = save(config)
            
            return config
        } catch {
            print("[AppConfigStore] Backup load failed: \(error)")
            return nil
        }
    }
    
    private static func migrateConfig(_ oldConfig: AppConfig) -> AppConfig {
        var newConfig = oldConfig
        
        // Migrate from version 2 to 3 (add pod support)
        if oldConfig.configVersion < 3 {
            newConfig.podConfigs = []
            newConfig.lastUsedPodId = nil
            
            // Get device name based on platform
            #if os(iOS)
            newConfig.deviceName = UIDevice.current.name
            #elseif os(macOS)
            // On macOS, use ProcessInfo to get the hostname
            newConfig.deviceName = ProcessInfo.processInfo.hostName
            #endif
            
            newConfig.configVersion = 3
            print("[AppConfigStore] Migrated config from version \(oldConfig.configVersion) to 3 (added pod support)")
        }
        
        return newConfig
    }
    
    // In AppConfigStore.swift, add these methods:
    static func updateDiscoveredTags(podId: UUID, tags: [String]) {
        var config = load()
        if let index = config.podConfigs.firstIndex(where: { $0.id == podId }) {
            // Merge with existing discovered tags
            let existingTags = Set(config.podConfigs[index].discoveredTags)
            let newTags = Set(tags)
            config.podConfigs[index].discoveredTags = Array(existingTags.union(newTags)).sorted()
            save(config)
        }
    }

    static func refreshPodCache(podId: UUID, nodes: [PodNode], tags: [String], discoveredTags: [String]? = nil) {
        var config = load()
        if let index = config.podConfigs.firstIndex(where: { $0.id == podId }) {
            config.podConfigs[index].discoveredNodes = nodes
            config.podConfigs[index].cachedTags = tags
            config.podConfigs[index].lastRefresh = Date()
            
            // Update discovered tags if provided
            if let discovered = discoveredTags {
                let existingTags = Set(config.podConfigs[index].discoveredTags)
                let newTags = Set(discovered)
                config.podConfigs[index].discoveredTags = Array(existingTags.union(newTags)).sorted()
            }
            
            save(config)
        }
    }
    
    // MARK: - Pod-specific convenience methods
    
    static func addPodConfig(_ pod: PodConfig) {
        var config = load()
        config.podConfigs.append(pod)
        config.lastUsedPodId = pod.id
        save(config)
    }
    
    static func updatePodConfig(_ pod: PodConfig) {
        var config = load()
        if let index = config.podConfigs.firstIndex(where: { $0.id == pod.id }) {
            config.podConfigs[index] = pod
            save(config)
        }
    }
    
    static func removePodConfig(id: UUID) {
        var config = load()
        config.podConfigs.removeAll { $0.id == id }
        if config.lastUsedPodId == id {
            config.lastUsedPodId = config.podConfigs.first?.id
        }
        save(config)
    }
    
    static func getPodConfig(id: UUID) -> PodConfig? {
        let config = load()
        return config.podConfigs.first { $0.id == id }
    }
    
    static func updateDeviceName(_ name: String) {
        var config = load()
        config.deviceName = name
        save(config)
    }

    
    // Helper method to get default device name for current platform
    static func getDefaultDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return ProcessInfo.processInfo.hostName
        #endif
    }
}
