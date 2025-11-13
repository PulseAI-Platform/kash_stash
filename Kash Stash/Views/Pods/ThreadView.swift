//
//  ThreadView.swift
//  Kash Stash
//
//  Created by Matt on 11/12/25.
//

//
//  ThreadView.swift
//  Kash Stash
//
//  Thread view for showing a post and all its replies
//

import SwiftUI

struct ThreadView: View {
    let originalDigest: Digest
    let allDigests: [Digest]
    let pod: PodConfig
    
    @State private var replyingToDigest: Digest? = nil
    @State private var expandedReplies: Set<String> = []
    @Environment(\.dismiss) var dismiss
    
    // Get direct replies to a specific digest
    private func getReplies(to digestId: String) -> [Digest] {
        return allDigests
            .filter { $0.repliesTo == digestId }
            .sorted { $0.createdAt < $1.createdAt }
    }
    
    // Count total replies including nested ones
    private func countAllReplies(to digestId: String) -> Int {
        let directReplies = getReplies(to: digestId)
        var count = directReplies.count
        for reply in directReplies {
            count += countAllReplies(to: reply.id)
        }
        return count
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Original post
                    VStack(alignment: .leading, spacing: 12) {
                        // Post header
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.purple)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                if let device = extractDevice(from: originalDigest) {
                                    Text(device)
                                        .font(.headline)
                                }
                                
                                HStack {
                                    if let sourceNode = originalDigest.sourceNode {
                                        Label(sourceNode, systemImage: "server.rack")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(originalDigest.createdAt, style: .relative)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                        
                        // Post content
                        if !originalDigest.title.isEmpty && originalDigest.title != "Untitled" {
                            Text(originalDigest.title)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Text(cleanContent(originalDigest.content))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Tags
                        if !originalDigest.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(originalDigest.tags.sorted(), id: \.self) { tag in
                                        if !tag.hasPrefix("from-") {
                                            Text("#\(tag)")
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.purple.opacity(0.15))
                                                .foregroundColor(.purple)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Action buttons
                        HStack(spacing: 20) {
                            Button(action: { replyingToDigest = originalDigest }) {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            let replyCount = countAllReplies(to: originalDigest.id)
                            if replyCount > 0 {
                                Label("\(replyCount) repl\(replyCount == 1 ? "y" : "ies")",
                                      systemImage: "bubble.left.and.bubble.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    
                    Divider()
                    
                    // Replies section
                    let directReplies = getReplies(to: originalDigest.id)
                    if !directReplies.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Replies")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.vertical, 12)
                                .background(Color(.systemGroupedBackground))
                            
                            ForEach(directReplies) { reply in
                                ReplyRow(
                                    reply: reply,
                                    allDigests: allDigests,
                                    pod: pod,
                                    depth: 0,
                                    expandedReplies: $expandedReplies,
                                    onReply: { digest in
                                        replyingToDigest = digest
                                    }
                                )
                                
                                if reply != directReplies.last {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.3))
                            
                            Text("No replies yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Be the first to reply!")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button(action: { replyingToDigest = originalDigest }) {
                                Label("Write a Reply", systemImage: "square.and.pencil")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 24)
                                    .background(Color.purple)
                                    .cornerRadius(10)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
            }
            .navigationTitle("Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $replyingToDigest) { digest in
            ReplyPostView(replyingTo: digest, pod: pod)
        }
    }
    
    private func extractDevice(from digest: Digest) -> String? {
        for tag in digest.tags {
            if tag.hasPrefix("from-") {
                return String(tag.dropFirst(5))
            }
        }
        return nil
    }
    
    private func cleanContent(_ content: String) -> String {
        var cleaned = content
        
        // Remove @reply: references
        if let range = cleaned.range(of: "@reply:") {
            if let spaceIndex = cleaned[range.upperBound...].firstIndex(of: " ") {
                cleaned.removeSubrange(range.lowerBound..<cleaned.index(after: spaceIndex))
            }
        }
        
        // Remove @mention references
        if cleaned.hasPrefix("@") {
            if let spaceIndex = cleaned.firstIndex(of: " ") {
                cleaned = String(cleaned[cleaned.index(after: spaceIndex)...])
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Recursive reply row component
struct ReplyRow: View {
    let reply: Digest
    let allDigests: [Digest]
    let pod: PodConfig
    let depth: Int
    @Binding var expandedReplies: Set<String>
    let onReply: (Digest) -> Void
    
    private var nestedReplies: [Digest] {
        allDigests
            .filter { $0.repliesTo == reply.id }
            .sorted { $0.createdAt < $1.createdAt }
    }
    
    private var isExpanded: Bool {
        expandedReplies.contains(reply.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Indentation for nested replies
                if depth > 0 {
                    Rectangle()
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 2)
                        .padding(.leading, CGFloat(depth * 20))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    // Reply header
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundColor(.purple.opacity(0.7))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            if let device = extractDevice(from: reply) {
                                Text(device)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            HStack(spacing: 8) {
                                Text(reply.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if depth > 0 {
                                    Label("Nested reply", systemImage: "arrow.turn.down.right")
                                        .font(.caption2)
                                        .foregroundColor(.purple)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        if !nestedReplies.isEmpty {
                            Button(action: { toggleExpanded() }) {
                                HStack(spacing: 4) {
                                    Text("\(nestedReplies.count)")
                                        .font(.caption)
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                }
                                .foregroundColor(.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    // Reply content
                    Text(cleanContent(reply.content))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Reply actions
                    HStack(spacing: 20) {
                        Button(action: { onReply(reply) }) {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                        
                        if !nestedReplies.isEmpty {
                            Label("\(nestedReplies.count) repl\(nestedReplies.count == 1 ? "y" : "ies")",
                                  systemImage: "bubble.left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(depth == 0 ? Color(.systemBackground) : Color(.systemGray6).opacity(0.5))
            
            // Nested replies (if expanded)
            if isExpanded && !nestedReplies.isEmpty {
                VStack(spacing: 0) {
                    ForEach(nestedReplies) { nestedReply in
                        ReplyRow(
                            reply: nestedReply,
                            allDigests: allDigests,
                            pod: pod,
                            depth: min(depth + 1, 3), // Limit nesting depth
                            expandedReplies: $expandedReplies,
                            onReply: onReply
                        )
                        
                        if nestedReply != nestedReplies.last {
                            Divider()
                                .padding(.leading, CGFloat((depth + 1) * 20 + 16))
                        }
                    }
                }
            }
        }
    }
    
    private func toggleExpanded() {
        if isExpanded {
            expandedReplies.remove(reply.id)
        } else {
            expandedReplies.insert(reply.id)
        }
    }
    
    private func extractDevice(from digest: Digest) -> String? {
        for tag in digest.tags {
            if tag.hasPrefix("from-") {
                return String(tag.dropFirst(5))
            }
        }
        return nil
    }
    
    private func cleanContent(_ content: String) -> String {
        var cleaned = content
        
        // Remove @mention references more thoroughly
        if let atIndex = cleaned.firstIndex(of: "@") {
            if let spaceIndex = cleaned[atIndex...].firstIndex(of: " ") {
                let nextCharIndex = cleaned.index(after: spaceIndex)
                if nextCharIndex < cleaned.endIndex {
                    cleaned = String(cleaned[nextCharIndex...])
                }
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
