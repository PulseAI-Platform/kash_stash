import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = KashStashViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {

                    // 1. Big warning if no endpoints
                    if viewModel.config.endpoints.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.yellow)
                        Text("HEY BUDDY")
                            .font(.largeTitle)
                            .fontWeight(.heavy)
                            .foregroundColor(.primary)
                        Text("YOU DON’T HAVE ANY ENDPOINTS CONFIGURED!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                        Text("Tap below to set up your first server/endpoint.\nUploading won’t work until you do.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .font(.body)
                            .padding()

                        NavigationLink(destination: ManageEndpointsView(viewModel: viewModel)) {
                            Text("Manage Endpoints")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: 320)
                                .background(Color.accentColor)
                                .cornerRadius(14)
                                .shadow(radius: 4)
                        }
                    }

                    // 2. Main Menu – only if endpoints exist (or always visible if you prefer)
                    if !viewModel.config.endpoints.isEmpty {
                        // Show current endpoint info
                        if let ep = viewModel.currentEndpoint {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current Endpoint:")
                                    .font(.headline)
                                Text(ep.name)
                                    .font(.title2)
                                if !ep.device.isEmpty {
                                    Text(ep.device)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text("No endpoint selected")
                                .foregroundColor(.red)
                        }

                        // Action menu
                        VStack(spacing: 16) {
                            NavigationLink(destination: QuickNoteView(viewModel: viewModel)) {
                                Text("Quick Note")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(10)
                            }
                            NavigationLink(destination: PhotoUploadView(viewModel: viewModel)) {
                                Text("Take Photo")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.top, 8)
                    }

                    // 3. Settings (always visible, or only if endpoints exist – your choice!)
                    VStack(spacing: 8) {
                        NavigationLink(destination: SwitchEndpointView(viewModel: viewModel)) {
                            Text("Switch Endpoint")
                                .frame(maxWidth: .infinity)
                        }
                        NavigationLink(destination: ManageEndpointsView(viewModel: viewModel)) {
                            Text("Manage Endpoints")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 8)

                    // 4. BLOG and MY NODE BUTTONS – always at bottom!
                    VStack(spacing: 18) {
                        Button(action: {
                            if let url = URL(string: "https://blog.pulseaiplatform.com") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Pulse AI Blog")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        }
                        Button(action: {
                            if let nodeName = viewModel.config.endpoints.first?.nodeName,
                               !nodeName.isEmpty,
                               let url = URL(string: "https://pulse-\(nodeName).xyzpulseinfra.com") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("My Node")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor((viewModel.config.endpoints.first.map { $0.nodeName.isEmpty } ?? true) ? .gray : .blue)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        }
                        .disabled(viewModel.config.endpoints.first.map { $0.nodeName.isEmpty } ?? true)
                    }
                    .padding(.vertical, 24)

                }
                .padding(.horizontal)
                .padding(.top, 32)
                .frame(maxWidth: 520)
                .frame(minHeight: UIScreen.main.bounds.height * 0.8, alignment: .top)
                .navigationTitle("Kash Stash")
            }
            .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Ensures ONLY stack view; never sidebar!
    }
}
