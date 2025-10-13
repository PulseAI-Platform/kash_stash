import SwiftUI

struct QuickNoteView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var noteText: String = ""
    @State private var tags: String = ""
    @State private var isUploading: Bool = false
    @State private var showResult: Bool = false
    @State private var uploadSuccess: Bool?

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Note")) {
                    TextEditor(text: $noteText)
                        .frame(height: 200)
                }
                Section(header: Text("Tags (comma separated)")) {
                    TextField("eg: review,quick", text: $tags)
                }
            }
            Button(action: uploadNote) {
                if isUploading { ProgressView() }
                else { Text("Upload") }
            }
            .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUploading || viewModel.currentEndpoint == nil)
            .padding()
        }
        .navigationTitle("Quick Note")
        .alert(isPresented: $showResult) {
            Alert(
                title: Text(uploadSuccess == true ? "Upload Complete" : "Upload Failed"),
                dismissButton: .default(Text("OK")) {
                    if uploadSuccess == true {
                        // Clear fields on success!
                        noteText = ""
                        tags = ""
                    }
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .onDisappear {
            // Optional: Clean on every close
            noteText = ""
            tags = ""
        }
    }

    func uploadNote() {
        guard let endpoint = viewModel.currentEndpoint else { return }
        isUploading = true
        KashStashUploader.uploadTextNote(
            text: noteText,
            tags: tags,
            endpoint: endpoint
        ) { success in
            isUploading = false
            uploadSuccess = success
            showResult = true
        }
    }
}
