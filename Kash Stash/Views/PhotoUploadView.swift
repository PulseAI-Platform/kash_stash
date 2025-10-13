import SwiftUI
import PhotosUI

struct PhotoUploadView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var image: UIImage?
    @State private var context: String = ""
    @State private var tags: String = ""
    @State private var isUploading: Bool = false
    @State private var uploadSuccess: Bool?
    @State private var showResult: Bool = false
    @State private var showPhotoPicker = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 250)
                            .cornerRadius(8)
                    } else {
                        Button("Take Photo / Choose Photo") {
                            showPhotoPicker = true
                        }
                    }
                }
                if image != nil {
                    Section(header: Text("Tags (comma separated)")) {
                        TextField("eg: debug,screenshot", text: $tags)
                    }
                    Section(header: Text("Context")) {
                        TextField("Describe this photo", text: $context)
                    }
                    Button(action: uploadPhoto) {
                        if isUploading { ProgressView() }
                        else { Text("Upload Photo") }
                    }
                    .disabled(isUploading || viewModel.currentEndpoint == nil)
                }
            }
        }
        .navigationTitle("Photo Upload")
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(selectedImage: $image)
        }
        .alert(isPresented: $showResult) {
            Alert(
                title: Text(uploadSuccess == true ? "Upload Complete" : "Upload Failed"),
                dismissButton: .default(Text("OK")) {
                    if uploadSuccess == true {
                        // Clear all fields!
                        image = nil
                        tags = ""
                        context = ""
                    }
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .onDisappear {
            // Optional: Clean on every close
            image = nil
            tags = ""
            context = ""
        }
    }

    func uploadPhoto() {
        guard let endpoint = viewModel.currentEndpoint,
              let img = image,
              let pngData = img.pngData() else { return }

        isUploading = true
        KashStashUploader.uploadPhoto(
            data: pngData,
            tags: tags,
            context: context,
            endpoint: endpoint
        ) { success in
            isUploading = false
            uploadSuccess = success
            showResult = true
        }
    }
}
