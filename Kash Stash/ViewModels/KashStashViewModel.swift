import Foundation
import Combine

class KashStashViewModel: ObservableObject {
    @Published var config: AppConfig
    @Published var selectedUploadDestination: UploadDestination = .endpointOnly
    
    init() {
        self.config = AppConfigStore.load()
        self.selectedUploadDestination = config.defaultUploadDestination
    }
    
    // Save changes on demand (call this after mutations)
    func save() {
        print("[ViewModel] Saving config with \(config.endpoints.count) endpoints and \(config.kashFiles.count) KashFiles")
        config.defaultUploadDestination = selectedUploadDestination
        AppConfigStore.save(config)
    }
    
    // Helper to set the current endpoint
    func setCurrentEndpoint(_ endpoint: KashStashEndpoint) {
        config.lastUsedEndpoint = endpoint.id
        save()
    }
    
    var currentEndpoint: KashStashEndpoint? {
        guard let id = config.lastUsedEndpoint else { return nil }
        return config.endpoints.first(where: { $0.id == id })
    }
    
    // Kash Files management
    var currentKashFiles: KashFilesConfig? {
        config.kashFiles.first(where: { $0.isActive }) ??
        (config.lastUsedKashFilesId != nil ? config.kashFiles.first(where: { $0.id == config.lastUsedKashFilesId }) : nil) ??
        config.kashFiles.first
    }
    
    func setActiveKashFiles(_ kf: KashFilesConfig) {
        print("[ViewModel] Setting active KashFiles: \(kf.name)")
        // Deactivate all others
        for i in config.kashFiles.indices {
            config.kashFiles[i].isActive = false
        }
        // Activate selected
        if let idx = config.kashFiles.firstIndex(where: { $0.id == kf.id }) {
            config.kashFiles[idx].isActive = true
            config.lastUsedKashFilesId = kf.id
        }
        save()
    }
    
    func addKashFiles(_ kf: KashFilesConfig) {
        print("[ViewModel] Adding KashFiles: \(kf.name)")
        var newKF = kf
        // If it's the first one, make it active
        if config.kashFiles.isEmpty {
            newKF.isActive = true
        }
        config.kashFiles.append(newKF)
        save()
    }
    
    func updateKashFiles(_ kf: KashFilesConfig) {
        print("[ViewModel] Updating KashFiles with id: \(kf.id), name: \(kf.name)")
        print("[ViewModel] Current KashFiles count before update: \(config.kashFiles.count)")
        
        if let idx = config.kashFiles.firstIndex(where: { $0.id == kf.id }) {
            print("[ViewModel] Found KashFiles at index \(idx), updating...")
            config.kashFiles[idx] = kf
        } else {
            print("[ViewModel] WARNING: Could not find KashFiles with id \(kf.id) to update!")
            print("[ViewModel] Current IDs: \(config.kashFiles.map { $0.id })")
        }
        
        print("[ViewModel] KashFiles count after update: \(config.kashFiles.count)")
        save()
    }
    
    func deleteKashFiles(_ kf: KashFilesConfig) {
        print("[ViewModel] Deleting KashFiles: \(kf.name)")
        config.kashFiles.removeAll(where: { $0.id == kf.id })
        if config.lastUsedKashFilesId == kf.id {
            config.lastUsedKashFilesId = config.kashFiles.first?.id
            // Make first one active if we deleted the active one
            if !config.kashFiles.isEmpty && !config.kashFiles.contains(where: { $0.isActive }) {
                config.kashFiles[0].isActive = true
            }
        }
        save()
    }
    
    // Recent tags
    func addRecentTags(_ tags: String) {
        RecentTagsManager.addTags(tags, to: &config)
        save()
    }
    
    var recentTagsList: [String] {
        RecentTagsManager.getRecentTagsString(from: config)
    }
    
    // Check available destinations
    var availableDestinations: [UploadDestination] {
        var destinations: [UploadDestination] = []
        if currentEndpoint != nil {
            destinations.append(.endpointOnly)
        }
        if currentKashFiles != nil {
            destinations.append(.kashFilesOnly)
        }
        if currentEndpoint != nil && currentKashFiles != nil {
            destinations.append(.both)
        }
        return destinations
    }
    
    // Add/edit/delete endpoints (existing code)
    func addEndpoint(_ ep: KashStashEndpoint) {
        print("[ViewModel] Adding endpoint: \(ep.name)")
        config.endpoints.append(ep)
        config.lastUsedEndpoint = ep.id
        save()
    }
    
    func updateEndpoint(_ ep: KashStashEndpoint) {
        print("[ViewModel] Updating endpoint: \(ep.name)")
        if let idx = config.endpoints.firstIndex(where: { $0.id == ep.id }) {
            config.endpoints[idx] = ep
            save()
        }
    }
    
    func deleteEndpoint(_ ep: KashStashEndpoint) {
        print("[ViewModel] Deleting endpoint: \(ep.name)")
        config.endpoints.removeAll(where: { $0.id == ep.id })
        if config.lastUsedEndpoint == ep.id {
            config.lastUsedEndpoint = config.endpoints.first?.id
        }
        save()
    }
}
