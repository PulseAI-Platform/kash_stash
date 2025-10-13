import Foundation
import Combine

class KashStashViewModel: ObservableObject {
    @Published var config: AppConfig
    
    init() {
        self.config = AppConfigStore.load()
    }
    
    // Save changes on demand (call this after mutations)
    func save() {
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
    
    // Add/edit/delete endpoints
    func addEndpoint(_ ep: KashStashEndpoint) {
        config.endpoints.append(ep)
        config.lastUsedEndpoint = ep.id
        save()
    }
    
    func updateEndpoint(_ ep: KashStashEndpoint) {
        if let idx = config.endpoints.firstIndex(where: { $0.id == ep.id }) {
            config.endpoints[idx] = ep
            save()
        }
    }
    
    func deleteEndpoint(_ ep: KashStashEndpoint) {
        config.endpoints.removeAll(where: { $0.id == ep.id })
        if config.lastUsedEndpoint == ep.id {
            config.lastUsedEndpoint = config.endpoints.first?.id
        }
        save()
    }
}
