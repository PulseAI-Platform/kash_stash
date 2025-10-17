import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = KashStashViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {

                    // 1. Big warning if no endpoints
                    if viewModel.config.endpoints.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .resizable()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.orange)
                                .accessibilityLabel("Warning")
                            
                            Text("Setup Required")
                                .font(.largeTitle)
                                .fontWeight(.heavy)
                                .foregroundColor(.primary)
                            
                            Text("No endpoints configured")
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            Text("Add your first server endpoint to start uploading content. The app won't function without at least one endpoint configured.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .font(.body)
                                .padding(.horizontal)

                            NavigationLink(destination: ManageEndpointsView(viewModel: viewModel)) {
                                Text("Manage Endpoints")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 24)
                                    .frame(maxWidth: 320)
                                    .background(Color.black)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                                    .cornerRadius(14)
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            }
                            .accessibilityHint("Opens endpoint management screen")
                        }
                    }

                    // 2. Main Menu – only if endpoints exist
                    if !viewModel.config.endpoints.isEmpty {
                        VStack(spacing: 24) {
                            // Current endpoint info
                            if let ep = viewModel.currentEndpoint {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Active Endpoint")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    Text(ep.name)
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    
                                    if !ep.device.isEmpty {
                                        Text("Device: \(ep.device)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            } else {
                                Text("No endpoint selected")
                                    .foregroundColor(.red)
                                    .font(.headline)
                            }

                            // Action buttons
                            VStack(spacing: 16) {
                                NavigationLink(destination: QuickNoteView(viewModel: viewModel)) {
                                    HStack {
                                        Image(systemName: "note.text")
                                            .font(.title3)
                                        Text("Quick Note")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.black)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                                    .cornerRadius(12)
                                }
                                .accessibilityHint("Create and upload a text note")
                                
                                NavigationLink(destination: PhotoUploadView(viewModel: viewModel)) {
                                    HStack {
                                        Image(systemName: "camera")
                                            .font(.title3)
                                        Text("Take Photo")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.black)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                                    .cornerRadius(12)
                                }
                                .accessibilityHint("Take and upload a photo")
                            }
                        }
                    }

                    // 3. Settings section
                    VStack(spacing: 16) {
                        NavigationLink(destination: SwitchEndpointView(viewModel: viewModel)) {
                            HStack {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.title3)
                                Text("Switch Endpoint")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white, lineWidth: 1.5)
                            )
                            .cornerRadius(10)
                        }
                        .accessibilityHint("Change active endpoint")
                        
                        NavigationLink(destination: ManageEndpointsView(viewModel: viewModel)) {
                            HStack {
                                Image(systemName: "gear")
                                    .font(.title3)
                                Text("Manage Endpoints")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white, lineWidth: 1.5)
                            )
                            .cornerRadius(10)
                        }
                        .accessibilityHint("Add, edit, or remove endpoints")
                    }

                    // 4. External link buttons
                    VStack(spacing: 16) {
                        Button(action: {
                            if let url = URL(string: "https://blog.pulseaiplatform.com") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "globe")
                                    .font(.title3)
                                Text("Pulse AI Blog")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white, lineWidth: 1.5)
                            )
                            .cornerRadius(10)
                        }
                        .accessibilityHint("Opens Pulse AI blog in browser")
                        
                        Button(action: {
                            if let nodeName = viewModel.config.endpoints.first?.nodeName,
                               !nodeName.isEmpty,
                               let url = URL(string: "https://pulse-\(nodeName).xyzpulseinfra.com") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "server.rack")
                                    .font(.title3)
                                Text("My Node")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(isMyNodeDisabled ? .gray : .white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(isMyNodeDisabled ? Color(.systemGray4) : Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isMyNodeDisabled ? Color(.systemGray3) : Color.white, lineWidth: 1.5)
                            )
                            .cornerRadius(10)
                        }
                        .disabled(isMyNodeDisabled)
                        .accessibilityHint(isMyNodeDisabled ? "No node configured" : "Opens your node dashboard in browser")
                    }
                    .padding(.vertical, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .frame(maxWidth: 520)
                .frame(minHeight: UIScreen.main.bounds.height * 0.8, alignment: .top)
                .navigationTitle("Kash Stash")
            }
            .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private var isMyNodeDisabled: Bool {
        viewModel.config.endpoints.first?.nodeName.isEmpty ?? true
    }
}
