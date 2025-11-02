import Foundation

struct KashFilesConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: String
    var key: String
    var isActive: Bool
    
    var baseURL: String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }
    
    init(id: UUID = UUID(), name: String, url: String, key: String, isActive: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.key = key
        self.isActive = isActive
    }
}
