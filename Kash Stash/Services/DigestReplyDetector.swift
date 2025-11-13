// Services/DigestReplyDetector.swift
import Foundation

class DigestReplyDetector {
    private let deviceName: String
    
    init(deviceName: String) {
        self.deviceName = deviceName
    }
    
    func analyzeDigests(_ digests: [Digest]) -> [Digest] {
        var analyzed = digests
        
        // First pass: identify my posts
        let myPostIds = Set(digests
            .filter { $0.tags.contains(deviceName) }
            .map { $0.id })
        
        // Mark my posts
        for i in analyzed.indices {
            if analyzed[i].tags.contains(deviceName) {
                analyzed[i].isMyPost = true
            }
        }
        
        // Second pass: identify replies to my posts
        for i in analyzed.indices {
            if let replyToId = extractReplyId(from: analyzed[i].content),
               myPostIds.contains(replyToId) {
                analyzed[i].isReplyToMe = true
                analyzed[i].repliesTo = replyToId
            }
        }
        
        return analyzed
    }
    
    private func extractReplyId(from content: String) -> String? {
        // For iOS 16+ you can use the new Regex builder
        if #available(iOS 16.0, *) {
            // Try different reply patterns
            let patterns = [
                /\@reply:([a-zA-Z0-9_-]+)/,
                />>([a-zA-Z0-9_-]+)/,
                /RE:([a-zA-Z0-9_-]+)/
            ]
            
            for pattern in patterns {
                if let match = try? pattern.firstMatch(in: content) {
                    return String(match.1)
                }
            }
        } else {
            // Fallback for older iOS versions using NSRegularExpression
            let patterns = [
                #"@reply:([a-zA-Z0-9_-]+)"#,
                #">>([a-zA-Z0-9_-]+)"#,
                #"RE:([a-zA-Z0-9_-]+)"#
            ]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) {
                    if match.numberOfRanges > 1 {
                        let idRange = Range(match.range(at: 1), in: content)!
                        return String(content[idRange])
                    }
                }
            }
        }
        
        return nil
    }
}
