import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct FileUploadView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String = ""
    @State private var selectedFileSize: String = ""
    @State private var selectedFileMimeType: String = "application/octet-stream"
    @State private var tags: String = ""
    @State private var caption: String = ""  // ADD THIS for file captions
    @State private var isUploading: Bool = false
    @State private var showResult: Bool = false
    @State private var uploadSuccess: Bool?
    @State private var uploadedURL: String?
    @State private var showFilePicker = false
    @State private var showDestinationPicker = false
    @State private var showTagSelection = false
    @State private var selectedDestination: UploadDestination = .kashFilesOnly  // DEFAULT TO KASH FILES
    
    // Computed property for available destinations (FILES ONLY)
    var fileUploadDestinations: [UploadDestination] {
        var destinations: [UploadDestination] = []
        if viewModel.currentKashFiles != nil {
            destinations.append(.kashFilesOnly)
            if viewModel.currentEndpoint != nil {
                destinations.append(.both)
            }
        }
        return destinations
    }
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("File")) {
                    if selectedFileURL != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: fileIconName)
                                    .font(.largeTitle)
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading) {
                                    Text(selectedFileName)
                                        .font(.headline)
                                        .lineLimit(2)
                                    Text(selectedFileSize)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(selectedFileMimeType)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button("Remove") {
                                    selectedFileURL = nil
                                    selectedFileName = ""
                                    selectedFileSize = ""
                                }
                                .foregroundColor(.red)
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        Button(action: { showFilePicker = true }) {
                            VStack {
                                Image(systemName: "doc.badge.plus")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                Text("Tap to choose file")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 100)
                            .background(Color(.systemGray6))
                        }
                    }
                }
                
                if selectedFileURL != nil {
                    // Upload destination - FILES GET SPECIAL TREATMENT
                    Section(header: Text("Upload Destination")) {
                        if fileUploadDestinations.count > 1 {
                            Button(action: {
                                showDestinationPicker = true
                            }) {
                                HStack {
                                    Text(selectedDestination.rawValue)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    
                                    HStack(spacing: 4) {
                                        if selectedDestination == .both {
                                            Image(systemName: "server.rack")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                        }
                                        if selectedDestination == .kashFilesOnly || selectedDestination == .both {
                                            Image(systemName: "icloud")
                                                .foregroundColor(.blue)
                                                .font(.caption)
                                        }
                                    }
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }
                            }
                        } else {
                            Text(selectedDestination.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Add caption field for "both" mode
                    if selectedDestination == .both {
                        Section(header: Text("File Caption/Note")) {
                            TextField("Add a note about this file", text: $caption)
                        }
                    }
                    
                    Section(header: Text("Tags (comma separated)")) {
                        HStack {
                            TextField("eg: document,report", text: $tags)
                            
                            Button(action: {
                                showTagSelection = true
                            }) {
                                Image(systemName: "tag")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            
            // Upload button - FIXED OVERLAPPING
            if selectedFileURL != nil {
                Button(action: uploadFile) {
                    Group {  // Use Group to avoid overlapping
                        if isUploading {
                            ProgressView()
                        } else {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                Text("Upload File")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(uploadButtonBackground)
                    .cornerRadius(10)
                }
                .disabled(uploadButtonDisabled)
                .padding()
            }
        }
        .navigationTitle("File Upload")
        .onAppear {
            // Set appropriate default for files
            if viewModel.currentKashFiles != nil {
                selectedDestination = viewModel.currentEndpoint != nil ? .both : .kashFilesOnly
            } else {
                // Can't upload files without Kash Files
                selectedDestination = .kashFilesOnly
            }
        }
        .sheet(isPresented: $showFilePicker) {
#if canImport(UIKit)
            DocumentPicker(
                selectedFileURL: $selectedFileURL,
                selectedFileName: $selectedFileName,
                selectedFileSize: $selectedFileSize,
                selectedFileMimeType: $selectedFileMimeType
            )
#endif
        }
        .sheet(isPresented: $showDestinationPicker) {
            // Custom destination picker for files only
            FileDestinationSheet(
                isPresented: $showDestinationPicker,
                selectedDestination: $selectedDestination,
                availableDestinations: fileUploadDestinations
            )
        }
        .sheet(isPresented: $showTagSelection) {
            TagSelectionView(
                viewModel: viewModel,
                selectedTags: $tags,
                isPresented: $showTagSelection
            )
        }
        .alert(isPresented: $showResult) {
            Alert(
                title: Text(uploadSuccess == true ? "Upload Complete" : "Upload Failed"),
                message: uploadMessage,
                dismissButton: .default(Text("OK")) {
                    if uploadSuccess == true {
                        // Remove this line - tags already saved in uploadFile
                        // viewModel.addRecentTags(tags)
                        // Clear fields
                        selectedFileURL = nil
                        selectedFileName = ""
                        selectedFileSize = ""
                        caption = ""
                        tags = ""
                    }
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
#if os(macOS)
        .onChange(of: showFilePicker) { newValue in
            if newValue {
                showFilePicker = false
                selectFileOnMac()
            }
        }
#endif
    }
    
    private var fileIconName: String {
        if selectedFileMimeType.hasPrefix("image/") { return "photo" }
        if selectedFileMimeType.hasPrefix("video/") { return "video" }
        if selectedFileMimeType.hasPrefix("audio/") { return "speaker.wave.2" }
        if selectedFileMimeType.contains("pdf") { return "doc.text" }
        if selectedFileMimeType.contains("zip") || selectedFileMimeType.contains("compressed") { return "doc.zipper" }
        if selectedFileMimeType.hasPrefix("text/") { return "doc.plaintext" }
        return "doc"
    }
    
    private var uploadButtonBackground: Color {
        uploadButtonDisabled ? Color.gray : Color.black
    }
    
    private var uploadButtonDisabled: Bool {
        selectedFileURL == nil ||
        isUploading ||
        viewModel.currentKashFiles == nil ||
        (selectedDestination == .both && viewModel.currentEndpoint == nil)
    }
    
    private var uploadMessage: Text? {
        if uploadSuccess == true {
            if let url = uploadedURL {
                return Text("File uploaded successfully!\n\nKash Files URL:\n\(url)")
            } else {
                return Text("File uploaded successfully!")
            }
        }
        return nil
    }
    
#if os(macOS)
    func selectFileOnMac() {
        let panel = NSOpenPanel()
        panel.title = "Select File"
        panel.message = "Choose a file to upload"
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedFileURL = url
            selectedFileName = url.lastPathComponent
            
            // Get file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? Int64 {
                selectedFileSize = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            } else {
                selectedFileSize = "Unknown size"
            }
            
            // Detect MIME type
            if let uti = UTType(filenameExtension: url.pathExtension) {
                selectedFileMimeType = uti.preferredMIMEType ?? "application/octet-stream"
            } else {
                selectedFileMimeType = "application/octet-stream"
            }
        }
    }
#endif
    
    func uploadFile() {
        guard let fileURL = selectedFileURL else { return }
        
#if canImport(UIKit)
        // Start accessing the security-scoped resource
        guard fileURL.startAccessingSecurityScopedResource() else {
            print("Failed to access file")
            return
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }
#endif
        
        do {
            let fileData = try Data(contentsOf: fileURL)
            isUploading = true
            
            // Capture tags value before async call
            let uploadTags = tags
            
            // Pass the caption as context for "both" mode
            KashStashUploader.uploadWithDestination(
                data: fileData,
                filename: selectedFileName,
                mimeType: selectedFileMimeType,
                tags: uploadTags,
                context: caption,  // Pass caption here
                destination: selectedDestination,
                endpoint: viewModel.currentEndpoint,
                kashFiles: viewModel.currentKashFiles
            ) { success, url in
                isUploading = false
                uploadSuccess = success
                uploadedURL = url
                
                // Save tags immediately on success, not in alert handler
                if success && !uploadTags.isEmpty {
                    viewModel.addRecentTags(uploadTags)
                }
                
                showResult = true
            }
        } catch {
            print("Error reading file: \(error)")
            uploadSuccess = false
            showResult = true
        }
    }
}

// Add this simple destination picker for files
struct FileDestinationSheet: View {
    @Binding var isPresented: Bool
    @Binding var selectedDestination: UploadDestination
    let availableDestinations: [UploadDestination]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(availableDestinations, id: \.self) { destination in
                    Button(action: {
                        selectedDestination = destination
                        isPresented = false
                    }) {
                        HStack {
                            Text(destination.rawValue)
                            Spacer()
                            if selectedDestination == destination {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Upload Destination")
            .navigationBarItems(trailing: Button("Cancel") {
                isPresented = false
            })
        }
    }
}

// MARK: - Document Picker

#if canImport(UIKit)
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedFileURL: URL?
    @Binding var selectedFileName: String
    @Binding var selectedFileSize: String
    @Binding var selectedFileMimeType: String
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .content])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            parent.selectedFileURL = url
            parent.selectedFileName = url.lastPathComponent
            
            // Get file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? Int64 {
                parent.selectedFileSize = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            } else {
                parent.selectedFileSize = "Unknown size"
            }
            
            // Detect MIME type
            if let uti = UTType(filenameExtension: url.pathExtension) {
                parent.selectedFileMimeType = uti.preferredMIMEType ?? "application/octet-stream"
            } else {
                parent.selectedFileMimeType = "application/octet-stream"
            }
        }
    }
}
#endif
