import SwiftUI
#if canImport(UIKit)
import PhotosUI
import UIKit
#else
import AppKit
#endif

struct PhotoUploadView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @Environment(\.presentationMode) var presentationMode
    
    #if canImport(UIKit)
    @State private var image: UIImage?
    #else
    @State private var image: NSImage?
    #endif
    
    @State private var context: String = ""
    @State private var tags: String = ""
    @State private var isUploading: Bool = false
    @State private var uploadSuccess: Bool?
    @State private var uploadedURL: String?
    @State private var showResult: Bool = false
    @State private var showPhotoPicker = false
    @State private var showDestinationPicker = false
    @State private var showTagSelection = false
    @State private var selectedDestination: UploadDestination = .endpointOnly

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if let img = image {
                        #if canImport(UIKit)
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 250)
                            .cornerRadius(8)
                        #else
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 250)
                            .cornerRadius(8)
                        #endif
                    } else {
                        Button("Take Photo / Choose Photo") {
                            #if os(macOS)
                            selectPhotoOnMac()
                            #else
                            showPhotoPicker = true
                            #endif
                        }
                    }
                }
                
                if image != nil {
                    // Upload destination
                    Section(header: Text("Upload Destination")) {
                        Button(action: {
                            showDestinationPicker = true
                        }) {
                            HStack {
                                Text(selectedDestination.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .disabled(viewModel.availableDestinations.count <= 1)
                    
                    Section(header: Text("Tags (comma separated)")) {
                        HStack {
                            TextField("eg: debug,screenshot", text: $tags)
                            Button(action: {
                                showTagSelection = true
                            }) {
                                Image(systemName: "tag")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if selectedDestination != .kashFilesOnly {
                        Section(header: Text("Context (for AI caption)")) {
                            TextField("Describe this photo", text: $context)
                        }
                    }
                    
                    Button(action: uploadPhoto) {
                        if isUploading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Upload Photo")
                        }
                    }
                    .disabled(isUploading || (selectedDestination == .endpointOnly && viewModel.currentEndpoint == nil))
                }
            }
        }
        .navigationTitle("Photo Upload")
        .onAppear {
            selectedDestination = viewModel.selectedUploadDestination
        }
        #if os(iOS)
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(selectedImage: $image)
        }
        #endif
        .sheet(isPresented: $showDestinationPicker) {
            UploadDestinationSheet(
                viewModel: viewModel,
                isPresented: $showDestinationPicker,
                selectedDestination: $selectedDestination
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
                message: uploadSuccess == true && uploadedURL != nil ? Text("URL: \(uploadedURL!)") : nil,
                dismissButton: .default(Text("OK")) {
                    if uploadSuccess == true {
                        // Clear all fields!
                        image = nil
                        tags = ""
                        context = ""
                        // Remove this line - tags already saved in uploadPhoto
                        // viewModel.addRecentTags(tags)
                    }
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    #if os(macOS)
    func selectPhotoOnMac() {
        let panel = NSOpenPanel()
        panel.title = "Select Photo"
        panel.message = "Choose a photo to upload"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            if let nsImage = NSImage(contentsOf: url) {
                self.image = nsImage
            }
        }
    }
    #endif

    func uploadPhoto() {
        guard let img = image else { return }
        
        var pngData: Data?
        
        #if canImport(UIKit)
        pngData = img.pngData()
        #else
        if let tiffData = img.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            pngData = bitmap.representation(using: .png, properties: [:])
        }
        #endif
        
        guard let data = pngData else { return }

        let filename = "photo_\(Int(Date().timeIntervalSince1970)).png"
        
        isUploading = true
        
        // Capture tags value before async call
        let uploadTags = tags
        
        KashStashUploader.uploadWithDestination(
            data: data,
            filename: filename,
            mimeType: "image/png",
            tags: uploadTags,
            context: context,
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
    }
}
