//
//  LinkedTextView.swift
//  Kash Stash
//
//  Created by Matt on 11/11/25.
//

// Views/Components/LinkedTextView.swift
import SwiftUI

struct LinkedTextView: View {
    let text: String
    let onLinkTap: ((URL) -> Void)?
    
    @State private var detectedLinks: [NSRange: URL] = [:]
    
    init(_ text: String, onLinkTap: ((URL) -> Void)? = nil) {
        self.text = text
        self.onLinkTap = onLinkTap
    }
    
    var body: some View {
        if detectedLinks.isEmpty {
            Text(text)
                .onAppear {
                    detectLinks()
                }
        } else {
            Text(attributedString)
        }
    }
    
    private var attributedString: AttributedString {
        var attributed = AttributedString(text)
        
        for (range, url) in detectedLinks {
            if let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].foregroundColor = .blue
                attributed[attributedRange].underlineStyle = .single
                attributed[attributedRange].link = url
            }
        }
        
        return attributed
    }
    
    private func detectLinks() {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []
        
        var links: [NSRange: URL] = [:]
        for match in matches {
            if let url = match.url {
                links[match.range] = url
            }
        }
        
        detectedLinks = links
    }
}
