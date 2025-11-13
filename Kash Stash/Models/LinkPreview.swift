//
//  LinkPreview.swift
//  Kash Stash
//
//  Created by Matt on 11/11/25.
//

// Models/LinkPreview.swift
import Foundation
import LinkPresentation

struct LinkPreviewData: Identifiable {
    let id = UUID()
    let url: URL
    var title: String?
    var description: String?
    var imageURL: URL?
    var iconURL: URL?
    
    init(url: URL) {
        self.url = url
    }
}
