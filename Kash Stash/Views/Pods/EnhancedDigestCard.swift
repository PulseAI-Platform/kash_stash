//
//  EnhancedDigestCard.swift
//  Kash Stash
//

import SwiftUI
import LinkPresentation

struct EnhancedDigestCard: View {
    let digest: Digest
    let replyCount: Int
    var onTap: (() -> Void)? = nil
    var onReply: (() -> Void)? = nil
    
    @State private var linkURLs: [URL] = []
    @State private var expandedText = false
    
    // Initialize with default reply count of 0 for backwards compatibility
    init(digest: Digest, replyCount: Int = 0, onTap: (() -> Void)? = nil, onReply: (() -> Void)? = nil) {
        self.digest = digest
        self.replyCount = replyCount
        self.onTap = onTap
        self.onReply = onReply
    }
    
    private var myDeviceName: String {
        let config = AppConfigStore.load()
        return config.endpoints.first?.device ?? "ios-device"
    }
    
    private var isReplyToMe: Bool {
        let cleanDeviceName = myDeviceName.lowercased().replacingOccurrences(of: " ", with: "-")
        
        // Must have actual reply syntax, not just be tagged with device name
        if digest.content.contains("@") {
            // Check for reply syntax targeting our device
            return digest.content.lowercased().contains(".\(cleanDeviceName)") ||
                   (digest.content.contains("@reply:") && digest.tags.contains(cleanDeviceName))
        }
        
        return false
    }

    private var isMyPost: Bool {
        let cleanDeviceName = myDeviceName.lowercased().replacingOccurrences(of: " ", with: "-")
        // It's my post if it has my device tag but is NOT a reply
        return digest.tags.contains(cleanDeviceName) && !digest.content.contains("@")
    }
    
    private var displayTitle: String {
        if !digest.title.isEmpty && digest.title != "Untitled" {
            return digest.title
        } else {
            let firstLine = digest.content.components(separatedBy: .newlines).first ?? digest.content
            let preview = String(firstLine.prefix(80))
            return preview + (firstLine.count > 80 ? "..." : "")
        }
    }
    
    private let itemFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = false  // Change to false to see actual dates
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with reply indicator and pod flags
            HStack {
                if digest.content.contains("@") {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.caption)
                            .foregroundColor(isReplyToMe ? .green : .blue)
                        
                        Text(isReplyToMe ? "to you" : "reply")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 4) {
                    ForEach(Array(digest.inPods.prefix(2)), id: \.self) { podName in
                        PodFlag(name: podName)
                    }
                    if digest.inPods.count > 2 {
                        Text("+\(digest.inPods.count - 2)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isReplyToMe {
                    Label("Reply to you", systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(4)
                }
                
                if isMyPost {
                    Label("You", systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            // Main content - tappable for expansion ONLY
            VStack(alignment: .leading, spacing: 8) {
                Text(displayTitle)
                    .font(.headline)
                    .fontWeight(isReplyToMe ? .bold : .semibold)
                
                Text(digest.content)
                    .font(.body)
                    .lineLimit(expandedText ? nil : 4)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    expandedText.toggle()
                }
            }
            
            // Media previews - NOT tappable through the card
            if !linkURLs.isEmpty {
                VStack(spacing: 8) {
                    ForEach(linkURLs.prefix(1), id: \.self) { url in
                        EnhancedLinkPreview(url: url)
                    }
                    
                    if linkURLs.count > 1 {
                        Text("+\(linkURLs.count - 1) more link\(linkURLs.count - 1 == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(digest.tags, id: \.self) { tag in
                        DigestTagChip(
                            tag: tag,
                            isHighlighted: tag == myDeviceName.lowercased().replacingOccurrences(of: " ", with: "-")
                        )
                    }
                }
            }
            
            // Action buttons - MUST BE HIGH PRIORITY BUTTONS
            HStack(spacing: 16) {
                // Reply button with high priority
                Button {
                    print("Reply button tapped for digest: \(digest.id)")
                    onReply?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.caption)
                        Text("Reply")
                            .font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                }
                .buttonStyle(HighPriorityButtonStyle())
                
                // Thread button - shows reply count and opens thread view
                if replyCount > 0 {
                    Button {
                        print("Thread button tapped for digest: \(digest.id)")
                        onTap?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.caption)
                            Text("\(replyCount)")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(replyCount == 1 ? "reply" : "replies")
                                .font(.caption)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.purple.opacity(0.1))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(HighPriorityButtonStyle())
                }
                
                // Share button
                Button {
                    shareDigest()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                        Text("Share")
                            .font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.gray.opacity(0.1))
                    .foregroundColor(.gray)
                    .cornerRadius(6)
                }
                .buttonStyle(HighPriorityButtonStyle())
                
                Spacer()
                
                // Date and source - USING ACTUAL CREATED DATE
                // Replace the date display section with this debug version:
                // Date and source - USING ACTUAL CREATED DATE
                VStack(alignment: .trailing, spacing: 2) {
                    // Remove the debug line
                    // Text("Raw: \(digest.createdAt)")
                    //     .font(.caption2)
                    //     .foregroundColor(.red)
                    
                    Text(digest.createdAt, formatter: itemFormatter)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let sourceNode = digest.sourceNode {
                        Label(sourceNode, systemImage: "server.rack")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(backgroundForDigest)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColorForDigest, lineWidth: 2)
        )
        .shadow(color: shadowColorForDigest, radius: replyCount > 0 ? 4 : 0, x: 0, y: 2)
        .onAppear {
            extractURLs()
        }
    }
    
    private var backgroundForDigest: Color {
        if isReplyToMe {
            return Color.green.opacity(0.05)
        } else if isMyPost {
            return Color.blue.opacity(0.05)
        } else if replyCount > 0 {
            return Color.purple.opacity(0.03)
        } else {
            return Color(.systemBackground)
        }
    }
    
    private var borderColorForDigest: Color {
        if isReplyToMe {
            return Color.green.opacity(0.3)
        } else if replyCount > 5 {
            return Color.purple.opacity(0.2)
        } else {
            return Color.clear
        }
    }
    
    private var shadowColorForDigest: Color {
        if replyCount > 10 {
            return Color.purple.opacity(0.1)
        } else if replyCount > 0 {
            return Color.black.opacity(0.05)
        } else {
            return Color.clear
        }
    }
    
    private func extractURLs() {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(
            in: digest.content,
            options: [],
            range: NSRange(location: 0, length: digest.content.utf16.count)
        ) ?? []
        
        linkURLs = matches.compactMap { $0.url }
    }
    
    private func shareDigest() {
        let text = "\(digest.title)\n\n\(digest.content)"
        
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else { return }
        
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            activityVC.popoverPresentationController?.sourceView = rootVC.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
        }
        
        rootVC.present(activityVC, animated: true)
        #endif
    }
}

// Custom button style to ensure buttons work properly
struct HighPriorityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Components used by EnhancedDigestCard

struct PodFlag: View {
    let name: String
    
    var body: some View {
        Text(name)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.2))
            .cornerRadius(4)
    }
}

struct DigestTagChip: View {
    let tag: String
    let isHighlighted: Bool
    
    var body: some View {
        Text("#\(tag)")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHighlighted ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.2))
            .foregroundColor(isHighlighted ? .blue : .primary)
            .cornerRadius(8)
    }
}

// Preview
struct EnhancedDigestCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack {
                EnhancedDigestCard(
                    digest: Digest(
                        id: "123",
                        title: "Sample Digest",
                        content: "Check out this cool website: https://www.apple.com and this article https://www.x.com/somethinginteresting",
                        tags: ["test", "sample", "links", "iperd"],
                        sourceNode: "Node 1",
                        createdAt: Date(),
                        inPods: ["Pod A", "Pod B"],
                        isMyPost: true
                    ),
                    replyCount: 5,
                    onTap: { print("Tapped thread") },
                    onReply: { print("Reply tapped") }
                )
                .padding()
                
                EnhancedDigestCard(
                    digest: Digest(
                        id: "124",
                        title: "",
                        content: "@pod-a.probes-test.xyzpulseinfra.com.123.iperd This is a reply to your post with a link: https://github.com/someproject",
                        tags: ["reply", "github", "iperd"],
                        sourceNode: "Node 2",
                        createdAt: Date().addingTimeInterval(-3600),
                        inPods: ["Pod A"],
                        isMyPost: false,
                        isReplyToMe: true
                    ),
                    replyCount: 0,
                    onTap: { print("Tapped thread") },
                    onReply: { print("Reply tapped") }
                )
                .padding()
                
                EnhancedDigestCard(
                    digest: Digest(
                        id: "125",
                        title: "Hot Discussion",
                        content: "This post has generated a lot of discussion!",
                        tags: ["trending", "discussion"],
                        sourceNode: "Node 3",
                        createdAt: Date().addingTimeInterval(-7200),
                        inPods: ["Pod A", "Pod B", "Pod C"],
                        isMyPost: false
                    ),
                    replyCount: 23,
                    onTap: { print("Tapped thread") },
                    onReply: { print("Reply tapped") }
                )
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}
