//
//  LinkPreviewService.swift
//  Kash Stash
//
//  Created by Matt on 11/11/25.
//

import Foundation
import LinkPresentation
import SwiftUI

class LinkPreviewService {
    static let shared = LinkPreviewService()
    private var cache: [URL: LinkPreviewData] = [:]
    private let queue = DispatchQueue(label: "link.preview.queue", attributes: .concurrent)
    
    func fetchPreview(for url: URL) async -> LinkPreviewData? {
        // Check cache first
        if let cached = getCached(url: url) {
            return cached
        }
        
        do {
            // Create a NEW provider for each request - this is the key fix!
            let metadataProvider = LPMetadataProvider()
            let metadata = try await metadataProvider.startFetchingMetadata(for: url)
            
            var preview = LinkPreviewData(url: url)
            preview.title = metadata.title
            
            // Try to get description from various metadata fields
            if let summary = metadata.value(forKey: "_summary") as? String {
                preview.description = summary
            } else if let desc = metadata.value(forKey: "description") as? String {
                preview.description = desc
            }
            
            // For now, we'll skip image URLs since they require more complex handling
            // The UI will show a default link icon instead
            
            // Cache the result
            setCached(preview, for: url)
            
            return preview
        } catch {
            print("Failed to fetch link preview for \(url): \(error)")
            
            // Create a basic preview with just the URL
            let basicPreview = LinkPreviewData(url: url)
            setCached(basicPreview, for: url)
            
            return basicPreview
        }
    }
    
    private func getCached(url: URL) -> LinkPreviewData? {
        queue.sync {
            cache[url]
        }
    }
    
    private func setCached(_ preview: LinkPreviewData, for url: URL) {
        queue.async(flags: .barrier) {
            self.cache[url] = preview
        }
    }
}
