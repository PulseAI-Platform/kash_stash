import Foundation

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
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL)
            return true
        } catch {
            print("Save error:", error)
            return false
        }
    }

    static func load() -> AppConfig {
        do {
            let data = try Data(contentsOf: configURL)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            return config
        } catch {
            print("Load error:", error)
            // Return empty/default config if missing/broken
            return AppConfig(endpoints: [], lastUsedEndpoint: nil)
        }
    }
}
