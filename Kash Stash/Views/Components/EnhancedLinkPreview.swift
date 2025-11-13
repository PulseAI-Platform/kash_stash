// Views/Components/EnhancedLinkPreview.swift

import SwiftUI
import WebKit
import AVKit
import LinkPresentation

struct EnhancedLinkPreview: View {
    let url: URL
    @State private var mediaType: MediaType = .unknown
    @State private var metadata: LPLinkMetadata?
    @State private var isLoading = true
    @State private var showingWebView = false
    
    enum MediaType {
        case unknown
        case youtube
        case twitter
        case image
        case video
        case website
    }
    
    var body: some View {
        Group {
            switch mediaType {
            case .youtube:
                YouTubePreview(url: url)
                    .frame(height: 200)
                
            case .twitter:
                // For Twitter/X, show a taller preview
                TwitterLinkPreview(url: url, metadata: metadata)
                    .frame(minHeight: 250, maxHeight: 400)
                    .onTapGesture {
                        showingWebView = true
                    }
                
            case .image:
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .cornerRadius(12)
                } placeholder: {
                    ProgressView()
                        .frame(height: 200)
                }
                
            case .video:
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 250)
                    .cornerRadius(12)
                    
            default:
                if let metadata = metadata {
                    RichLinkPreview(metadata: metadata)
                        .frame(minHeight: 120, maxHeight: 250)
                        .onTapGesture {
                            UIApplication.shared.open(url)
                        }
                } else if isLoading {
                    BasicLinkPreview(url: url, title: "Loading...")
                } else {
                    BasicLinkPreview(url: url, title: nil)
                        .onTapGesture {
                            UIApplication.shared.open(url)
                        }
                }
            }
        }
        .sheet(isPresented: $showingWebView) {
            NavigationView {
                WebView(url: url)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle(url.host ?? "Web")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingWebView = false
                            }
                        }
                    }
            }
        }
        .task {
            await loadMetadata()
        }
    }
    
    private func loadMetadata() async {
        detectMediaType()
        
        // Don't load metadata for direct media files
        guard mediaType != .image && mediaType != .video else {
            isLoading = false
            return
        }
        
        let provider = LPMetadataProvider()
        provider.timeout = 5.0 // 5 second timeout for performance
        
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            await MainActor.run {
                self.metadata = metadata
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func detectMediaType() {
        let urlString = url.absoluteString.lowercased()
        
        if urlString.contains("youtube.com") || urlString.contains("youtu.be") {
            mediaType = .youtube
        } else if urlString.contains("twitter.com") || urlString.contains("x.com") {
            mediaType = .twitter
        } else if urlString.hasSuffix(".jpg") || urlString.hasSuffix(".jpeg") ||
                  urlString.hasSuffix(".png") || urlString.hasSuffix(".gif") ||
                  urlString.hasSuffix(".webp") {
            mediaType = .image
        } else if urlString.hasSuffix(".mp4") || urlString.hasSuffix(".mov") ||
                  urlString.hasSuffix(".m4v") {
            mediaType = .video
        } else {
            mediaType = .website
        }
    }
}

// Twitter preview with better height
struct TwitterLinkPreview: View {
    let url: URL
    let metadata: LPLinkMetadata?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "xmark.app.fill")
                    .font(.title2)
                    .foregroundColor(.black)
                
                Text("X (Twitter)")
                    .font(.headline)
                
                Spacer()
                
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal)
            .padding(.top)
            
            if let metadata = metadata {
                VStack(alignment: .leading, spacing: 8) {
                    if let title = metadata.title {
                        Text(title)
                            .font(.headline)
                            .lineLimit(3)
                            .padding(.horizontal)
                    }
                    
                    // Show image if available with larger size
                    if let imageProvider = metadata.imageProvider {
                        LinkPreviewImage(imageProvider: imageProvider)
                            .frame(maxHeight: 250)
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                }
            }
            
            Text("Tap to view on X")
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// Rich link preview for general websites
struct RichLinkPreview: View {
    let metadata: LPLinkMetadata
    @State private var image: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image if available
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxHeight: 150)
                    .clipped()
                    .cornerRadius(8)
            }
            
            // Title and description
            VStack(alignment: .leading, spacing: 4) {
                if let title = metadata.title {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                }
                
                if let url = metadata.url?.host {
                    HStack {
                        Image(systemName: "link.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let imageProvider = metadata.imageProvider else { return }
        
        // Use completion handler version
        imageProvider.loadObject(ofClass: UIImage.self) { image, error in
            if let image = image as? UIImage {
                Task { @MainActor in
                    self.image = image
                }
            }
        }
    }
}

// Helper view for loading images from NSItemProvider
struct LinkPreviewImage: View {
    let imageProvider: NSItemProvider
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
                    .frame(height: 100)
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        // Use completion handler version
        imageProvider.loadObject(ofClass: UIImage.self) { image, error in
            if let image = image as? UIImage {
                Task { @MainActor in
                    self.image = image
                }
            }
        }
    }
}

// YouTube preview with thumbnail
struct YouTubePreview: View {
    let url: URL
    
    var body: some View {
        if let videoId = extractYouTubeId(from: url) {
            // Use thumbnail instead of embedding for performance
            AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg")) { image in
                image
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                            .shadow(radius: 5)
                    )
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        ProgressView()
                    )
            }
            .cornerRadius(12)
            .onTapGesture {
                UIApplication.shared.open(url)
            }
        } else {
            BasicLinkPreview(url: url, title: "YouTube Video")
                .onTapGesture {
                    UIApplication.shared.open(url)
                }
        }
    }
    
    private func extractYouTubeId(from url: URL) -> String? {
        if url.host?.contains("youtube.com") == true {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?
                .value
        } else if url.host?.contains("youtu.be") == true {
            return url.pathComponents.last
        }
        return nil
    }
}

// Simple web view for when needed
struct WebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.layer.cornerRadius = 12
        webView.clipsToBounds = true
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.load(URLRequest(url: url))
    }
}

// Basic link preview fallback
struct BasicLinkPreview: View {
    let url: URL
    let title: String?
    
    var body: some View {
        HStack {
            Image(systemName: "link.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text(title ?? url.host ?? "Link")
                    .font(.subheadline)
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}
