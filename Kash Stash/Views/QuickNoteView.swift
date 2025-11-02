import SwiftUI

struct QuickNoteView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var noteText: String = ""
    @State private var tags: String = ""
    @State private var isUploading: Bool = false
    @State private var showResult: Bool = false
    @State private var uploadSuccess: Bool?
    @State private var uploadedURL: String?
    @State private var showDestinationPicker = false
    @State private var showTagSelection = false
    @State private var selectedDestination: UploadDestination = .endpointOnly

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Note")) {
                    TextEditor(text: $noteText)
                        .frame(height: 200)
                }
                
                // Upload destination
                Section(header: Text("Upload Destination")) {
                    Button(action: {
                        showDestinationPicker = true
                    }) {
                        HStack {
                            Text(selectedDestination.rawValue)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            // Show icons for clarity
                            HStack(spacing: 4) {
                                if selectedDestination == .endpointOnly || selectedDestination == .both {
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
                }
                .disabled(viewModel.availableDestinations.count <= 1)
                
                Section(header: Text("Tags (comma separated)")) {
                    HStack {
                        TextField("eg: review,quick", text: $tags)
                        
                        Button(action: {
                            showTagSelection = true
                        }) {
                            Image(systemName: "tag")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Show recent tags as chips for quick selection
                    if !viewModel.recentTagsList.isEmpty && tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Array(viewModel.recentTagsList.prefix(5)), id: \.self) { tag in
                                    Button(action: {
                                        if tags.isEmpty {
                                            tags = tag
                                        } else {
                                            tags += ",\(tag)"
                                        }
                                    }) {
                                        Text(tag)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Upload button
            Button(action: uploadNote) {
                if isUploading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Upload Note")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .background(uploadButtonBackground)
            .cornerRadius(10)
            .disabled(uploadButtonDisabled)
            .padding()
        }
        .navigationTitle("Quick Note")
        .onAppear {
            selectedDestination = viewModel.selectedUploadDestination
        }
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
                message: uploadMessage,
                dismissButton: .default(Text("OK")) {
                    if uploadSuccess == true {
                        // Save tags to recent
                        viewModel.addRecentTags(tags)
                        // Clear fields on success
                        noteText = ""
                        tags = ""
                    }
                    if uploadSuccess == true {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            )
        }
    }
    
    private var uploadButtonBackground: Color {
        uploadButtonDisabled ? Color.gray : Color.black
    }
    
    private var uploadButtonDisabled: Bool {
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNote.isEmpty ||
               isUploading ||
               (selectedDestination == .endpointOnly && viewModel.currentEndpoint == nil) ||
               (selectedDestination == .kashFilesOnly && viewModel.currentKashFiles == nil) ||
               (selectedDestination == .both && (viewModel.currentEndpoint == nil || viewModel.currentKashFiles == nil))
    }
    
    private var uploadMessage: Text? {
        if uploadSuccess == true {
            if let url = uploadedURL {
                return Text("Note uploaded successfully!\n\nKash Files URL:\n\(url)")
            } else if selectedDestination == .endpointOnly {
                return Text("Note uploaded to endpoint successfully!")
            } else {
                return Text("Note uploaded successfully!")
            }
        }
        return nil
    }

    func uploadNote() {
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return }
        
        isUploading = true
        
        let filename = "note_\(Int(Date().timeIntervalSince1970)).txt"
        let noteData = trimmedNote.data(using: .utf8) ?? Data()
        
        KashStashUploader.uploadWithDestination(
            data: noteData,
            filename: filename,
            mimeType: "text/plain",
            tags: tags,
            context: "", // No context needed for text notes
            destination: selectedDestination,
            endpoint: viewModel.currentEndpoint,
            kashFiles: viewModel.currentKashFiles
        ) { success, url in
            isUploading = false
            uploadSuccess = success
            uploadedURL = url
            showResult = true
        }
    }
}
