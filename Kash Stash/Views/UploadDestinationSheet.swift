import SwiftUI

struct UploadDestinationSheet: View {
    @ObservedObject var viewModel: KashStashViewModel
    @Binding var isPresented: Bool
    @Binding var selectedDestination: UploadDestination
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header info
                VStack(alignment: .leading, spacing: 12) {
                    if let endpoint = viewModel.currentEndpoint {
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundColor(.green)
                            Text("Endpoint: \(endpoint.name)")
                                .font(.caption)
                        }
                    }
                    
                    if let kashFiles = viewModel.currentKashFiles {
                        HStack {
                            Image(systemName: "icloud")
                                .foregroundColor(.blue)
                            Text("Kash Files: \(kashFiles.name)")
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                
                List {
                    ForEach(viewModel.availableDestinations, id: \.self) { destination in
                        Button(action: {
                            selectedDestination = destination
                            viewModel.selectedUploadDestination = destination
                            viewModel.save()
                            isPresented = false
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(destination.rawValue)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text(destinationDescription(for: destination))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedDestination == destination {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Upload Destination")
            .navigationBarItems(
                trailing: Button("Cancel") {
                    isPresented = false
                }
            )
        }
    }
    
    func destinationDescription(for destination: UploadDestination) -> String {
        switch destination {
        case .endpointOnly:
            return "Upload directly to your endpoint for AI processing"
        case .kashFilesOnly:
            return "Upload to Kash Files cloud storage only"
        case .linkAndCaption:
            return "Upload to Kash Files and create a link digest"
        case .both:
            return "Upload to Kash Files, create link digest, and send to AI"
        }
    }
}
