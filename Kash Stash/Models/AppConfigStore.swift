import Foundation

struct AppConfig: Codable, Equatable {
    var endpoints: [KashStashEndpoint]
    var lastUsedEndpoint: UUID?
    
    var kashFiles: [KashFilesConfig] = []
    var lastUsedKashFilesId: UUID?
    var recentTags: [RecentTag] = []
    var defaultUploadDestination: UploadDestination = .endpointOnly
    
    var configVersion: Int = 2
}

enum UploadDestination: String, Codable, CaseIterable {
    case endpointOnly = "Endpoint Only"
    case kashFilesOnly = "Kash Files Only"
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
            
            print("[AppConfigStore] Successfully saved config with \(config.endpoints.count) endpoints and \(config.kashFiles.count) KashFiles")
            return true
        } catch {
            print("[AppConfigStore] SAVE ERROR: \(error)")
            print("[AppConfigStore] Failed config had \(config.endpoints.count) endpoints and \(config.kashFiles.count) KashFiles")
            return false
        }
    }

    static func load() -> AppConfig {
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            var config = try decoder.decode(AppConfig.self, from: data)
            
            // Migrate old configs
            if config.configVersion < 2 {
                config = migrateConfig(config)
            }
            
            print("[AppConfigStore] Successfully loaded config with \(config.endpoints.count) endpoints and \(config.kashFiles.count) KashFiles")
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
            print("[AppConfigStore] Successfully loaded backup with \(config.endpoints.count) endpoints and \(config.kashFiles.count) KashFiles")
            
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
        newConfig.configVersion = 2
        print("[AppConfigStore] Migrated config from version \(oldConfig.configVersion) to 2")
        return newConfig
    }
}
