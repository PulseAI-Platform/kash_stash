//
//  ReplyPostView.swift
//  Kash Stash
//
//  Created by Matt on 11/11/25.
//

import SwiftUI
import PhotosUI

struct ReplyPostView: View {
    @Environment(\.dismiss) var dismiss
    let replyingTo: Digest
    let pod: PodConfig
    
    @State private var replyText = ""
    @State private var isPosting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var postSuccessful = false
    
    // File attachment states
    @State private var showAttachmentOptions = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var attachedFileData: Data?
    @State private var attachedFileName: String?
    @State private var attachedMimeType: String?
    @State private var showFilePicker = false
    
    // Tag management
    @State private var selectedTags: Set<String> = []
    @State private var showTagEditor = false
    @State private var customTagInput = ""
    @State private var customTags: Set<String> = []
    
    // Extract the device that sent the original message
    private var originalSenderDevice: String? {
        for tag in replyingTo.tags {
            if tag.hasPrefix("from-") {
                return String(tag.dropFirst(5))
            }
        }
        return nil
    }
    
    // Identify shared pod tags that should be mandatory
    private var sharedPodTags: Set<String> {
        // Tags that are in the pod's cached tags AND in the original post
        let podTagsSet = Set(pod.cachedTags)
        let postTags = Set(replyingTo.tags)
        return podTagsSet.intersection(postTags)
    }
    
    // Get available tags for editing (excluding system tags)
    private var editableTags: [String] {
        replyingTo.tags.filter { tag in
            !tag.hasPrefix("from-") &&
            !sharedPodTags.contains(tag) && // Don't show shared tags as editable
            tag != pod.name.lowercased().replacingOccurrences(of: " ", with: "-") &&
            tag != "reply"
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Header showing what we're replying to
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .foregroundColor(.blue)
                            Text("Replying to")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let sender = originalSenderDevice {
                                Text("from \(sender)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        // Original post preview
                        VStack(alignment: .leading, spacing: 4) {
                            Text(digestTitle)
                                .font(.headline)
                                .lineLimit(1)
                            
                            Text(replyingTo.content)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                            
                            // Show original tags
                            if !replyingTo.tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) {
                                        ForEach(replyingTo.tags, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.purple.opacity(0.15))
                                                .foregroundColor(.purple)
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                            
                            HStack {
                                if let sourceNode = replyingTo.sourceNode {
                                    Label(sourceNode, systemImage: "server.rack")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text(replyingTo.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    .background(Color(.systemGroupedBackground))
                    
                    // Reply text editor
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Reply")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top)
                        
                        TextEditor(text: $replyText)
                            .padding(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .frame(minHeight: 120)
                            .padding(.horizontal)
                        
                        // Tag selection
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Tags to Include")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Button(action: { showTagEditor.toggle() }) {
                                    Label(showTagEditor ? "Hide" : "Edit", systemImage: "tag.circle")
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal)
                            
                            if showTagEditor {
                                // Custom tag input
                                HStack {
                                    TextField("Add custom tag", text: $customTagInput)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .onSubmit {
                                            addCustomTag()
                                        }
                                    
                                    Button("Add") {
                                        addCustomTag()
                                    }
                                    .disabled(customTagInput.isEmpty)
                                }
                                .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        // Pod name tag (mandatory)
                                        let podTag = pod.name.lowercased().replacingOccurrences(of: " ", with: "-")
                                        TagChip(
                                            tag: podTag,
                                            isSelected: true,
                                            isMandatory: true,
                                            onTap: { }
                                        )
                                        
                                        // Shared pod tags (mandatory)
                                        ForEach(Array(sharedPodTags).sorted(), id: \.self) { tag in
                                            TagChip(
                                                tag: tag,
                                                isSelected: true,
                                                isMandatory: true,
                                                onTap: { }
                                            )
                                        }
                                        
                                        // Other tags from original post (selectable)
                                        ForEach(editableTags, id: \.self) { tag in
                                            TagChip(
                                                tag: tag,
                                                isSelected: selectedTags.contains(tag),
                                                isMandatory: false,
                                                onTap: {
                                                    if selectedTags.contains(tag) {
                                                        selectedTags.remove(tag)
                                                    } else {
                                                        selectedTags.insert(tag)
                                                    }
                                                }
                                            )
                                        }
                                        
                                        // Custom tags (removable)
                                        ForEach(Array(customTags).sorted(), id: \.self) { tag in
                                            HStack(spacing: 2) {
                                                Text("#\(tag)")
                                                    .font(.caption)
                                                Button(action: {
                                                    customTags.remove(tag)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.caption2)
                                                }
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundColor(.green)
                                            .cornerRadius(8)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                
                                Text("Locked tags are shared in the pod. Tap to add/remove optional tags.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            }
                        }
                        
                        // Attachment indicator
                        if attachedFileName != nil {
                            HStack {
                                Image(systemName: "paperclip")
                                Text(attachedFileName ?? "File")
                                    .font(.caption)
                                Spacer()
                                Button(action: { clearAttachment() }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                        
                        // Attachment buttons
                        HStack(spacing: 16) {
                            Button(action: { showAttachmentOptions = true }) {
                                Label("Attach File", systemImage: "paperclip")
                                    .font(.caption)
                            }
                            .disabled(attachedFileName != nil)
                            
                            Spacer()
                            
                            Text("\(replyText.count) chars")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
            }
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isPosting ? "Posting..." : "Post") {
                        postReply()
                    }
                    .disabled(replyText.isEmpty || isPosting)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // Pre-select the non-mandatory tags from the original post
            selectedTags = Set(editableTags)
        }
        .confirmationDialog("Add Attachment", isPresented: $showAttachmentOptions) {
            Button("Photo/Video") {
                showFilePicker = true
            }
            
            Button("Cancel", role: .cancel) { }
        }
        .photosPicker(
            isPresented: $showFilePicker,
            selection: $selectedItem,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedItem) { newItem in
            Task {
                await loadAttachment(from: newItem)
            }
        }
        .alert("Success", isPresented: $postSuccessful) {
            Button("OK") { dismiss() }
        } message: {
            Text("Reply posted successfully!")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var digestTitle: String {
        if !replyingTo.title.isEmpty && replyingTo.title != "Untitled" {
            return replyingTo.title
        } else {
            let firstLine = replyingTo.content.components(separatedBy: .newlines).first ?? replyingTo.content
            return String(firstLine.prefix(50)) + (firstLine.count > 50 ? "..." : "")
        }
    }
    
    private func addCustomTag() {
        let cleanTag = customTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        
        if !cleanTag.isEmpty {
            customTags.insert(cleanTag)
            customTagInput = ""
        }
    }
    
    private func clearAttachment() {
        attachedFileData = nil
        attachedFileName = nil
        attachedMimeType = nil
        selectedItem = nil
    }
    
    private func loadAttachment(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        if let data = try? await item.loadTransferable(type: Data.self) {
            await MainActor.run {
                self.attachedFileData = data
                self.attachedFileName = "attachment_\(Int(Date().timeIntervalSince1970)).jpg"
                self.attachedMimeType = "image/jpeg"
            }
        }
    }
    
    private func postReply() {
        isPosting = true
        let config = AppConfigStore.load()
        
        guard let endpoint = config.endpoints.first else {
            errorMessage = "No endpoint configured. Please configure an endpoint in Settings first."
            showError = true
            isPosting = false
            return
        }
        
        let nodeName = endpoint.nodeName
        let cleanPodName = pod.name.lowercased().replacingOccurrences(of: " ", with: "-")
        
        // Use the original sender's device name if available
        let targetDevice = originalSenderDevice ?? "unknown"
        let replyRef = "@\(cleanPodName).probes-\(nodeName).xyzpulseinfra.com.\(replyingTo.id).\(targetDevice)"
        var fullReplyText = "\(replyRef) \(replyText)"
        
        // Handle attachment if present
        if let fileData = attachedFileData,
           let fileName = attachedFileName,
           let mimeType = attachedMimeType,
           let kashFiles = config.kashFiles.first {
            
            // Upload to Kash Files first
            KashFilesClient.uploadFile(
                data: fileData,
                filename: fileName,
                mimeType: mimeType,
                config: kashFiles
            ) { result in
                switch result {
                case .success(let response):
                    // Build the download URL
                    var downloadURL: String
                    if let download = response.download {
                        downloadURL = "\(kashFiles.baseURL)\(download)"
                    } else if let location = response.location {
                        downloadURL = "\(kashFiles.baseURL)/api/files/\(location)"
                    } else {
                        downloadURL = "\(kashFiles.baseURL)/files/\(fileName)"
                    }
                    
                    // Add the link to the reply
                    fullReplyText += "\n\n📎 Attachment: \(downloadURL)"
                    
                    // Now post the reply with the link
                    self.postReplyText(fullReplyText, endpoint: endpoint)
                    
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to upload attachment: \(error.localizedDescription)"
                        self.showError = true
                        self.isPosting = false
                    }
                }
            }
        } else {
            // No attachment, just post the reply
            postReplyText(fullReplyText, endpoint: endpoint)
        }
    }
    
    private func postReplyText(_ text: String, endpoint: KashStashEndpoint) {
        // Build tags - include mandatory tags, selected tags, and custom tags
        var tags = Set<String>()
        
        // Add mandatory pod tag
        let cleanPodName = pod.name.lowercased().replacingOccurrences(of: " ", with: "-")
        tags.insert(cleanPodName)
        
        // Add all shared pod tags (mandatory)
        tags.formUnion(sharedPodTags)
        
        // Add selected optional tags
        tags.formUnion(selectedTags)
        
        // Add custom tags
        tags.formUnion(customTags)
        
        // Add reply indicator
        tags.insert("reply")
        
        // The uploader will add our own from- tag automatically
        let finalTags = tags.joined(separator: ",")
        
        print("Posting reply with tags: \(finalTags)")
        
        // Use KashStashUploader which will add the from- tag automatically
        KashStashUploader.uploadTextNote(
            text: text,
            tags: finalTags,
            endpoint: endpoint
        ) { success in
            if success {
                postSuccessful = true
                isPosting = false
            } else {
                errorMessage = "Failed to post reply. Please check your endpoint configuration."
                showError = true
                isPosting = false
            }
        }
    }
}

// Tag chip component stays the same
struct TagChip: View {
    let tag: String
    let isSelected: Bool
    let isMandatory: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                if isMandatory {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                }
                Text("#\(tag)")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.purple : Color.secondary.opacity(0.2))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isMandatory ? Color.purple : Color.clear, lineWidth: 1)
            )
        }
        .disabled(isMandatory)
    }
}


// Preview
struct ReplyPostView_Previews: PreviewProvider {
    static var previews: some View {
        ReplyPostView(
            replyingTo: Digest(
                id: "123",
                title: "",
                content: "This is a sample post content that someone would reply to.",
                tags: ["tech", "news", "apple", "from-mobile"],
                sourceNode: "Node 1",
                createdAt: Date().addingTimeInterval(-3600),
                inPods: ["Tech Pod"],
                isMyPost: false,
                isReplyToMe: false,
                repliesTo: nil
            ),
            pod: PodConfig(
                name: "Tech Pod",
                entranceNodeUrl: "https://example.com",
                presharedKey: "test-key"
            )
        )
    }
}
