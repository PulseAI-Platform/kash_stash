import SwiftUI
#if os(macOS)
extension View {
    func fixedButtonStyle() -> some View {
        self
            .buttonStyle(PlainButtonStyle())
            .contentShape(Rectangle())
    }
}
#endif

struct ContentView: View {
    @StateObject var viewModel = KashStashViewModel()
    @State private var showQRImport = false
    @State private var showQRTextCapture = false
    @State private var podConfigs: [PodConfig] = []

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

                    // 2. Main Status – only if endpoints exist
                    if !viewModel.config.endpoints.isEmpty {
                        VStack(spacing: 12) {
                            // Endpoint info
                            if let ep = viewModel.currentEndpoint {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "server.rack")
                                            .foregroundColor(.green)
                                        Text("Active Endpoint")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                    }
                                    
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
                                HStack {
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundColor(.red)
                                    Text("No endpoint selected")
                                        .foregroundColor(.red)
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            
                            // Kash Files info
                            if let kf = viewModel.currentKashFiles {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "icloud.fill")
                                            .foregroundColor(.blue)
                                        Text("Kash Files")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Text("ACTIVE")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green)
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                    }
                                    
                                    Text(kf.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text(kf.url)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            
                            // Pods info
                            if !podConfigs.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "bubble.left.and.bubble.right.fill")
                                            .foregroundColor(.purple)
                                        Text("Pods")
                                            .font(.headline)
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Text("\(podConfigs.filter { $0.isActive }.count) ACTIVE")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple)
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                    }
                                    
                                    Text("\(podConfigs.count) pod\(podConfigs.count == 1 ? "" : "s") configured")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            
                            // Current upload destination indicator
                            HStack {
                                Image(systemName: "arrow.up.circle")
                                    .foregroundColor(.orange)
                                Text("Default Upload: \(viewModel.selectedUploadDestination.rawValue)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }
                    }

                    // 3. Settings section
                    VStack(spacing: 16) {
                        Button(action: {
                            showQRImport = true
                        }) {
                            HStack {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title3)
                                Text("Import from QR")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                        .accessibilityHint("Import configuration from QR code")
                        
                        // Scan & Upload Button
                        Button(action: {
                            showQRTextCapture = true
                        }) {
                            HStack {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.title3)
                                Text("Scan & Upload")
                                    .font(.headline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .cornerRadius(10)
                        }
                        .accessibilityHint("Scan barcodes or QR codes and upload as text")
                        
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
                        .disabled(viewModel.config.endpoints.count < 2)
                        .opacity(viewModel.config.endpoints.count < 2 ? 0.5 : 1.0)
                        
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
                        
                        NavigationLink(destination: KashFilesManagementView(viewModel: viewModel)) {
                            HStack {
                                Image(systemName: "icloud")
                                    .font(.title3)
                                Text("Manage Kash Files")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                
                                if viewModel.currentKashFiles != nil {
                                    Spacer()
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white, lineWidth: 1.5)
                            )
                            .cornerRadius(10)
                        }
                        .accessibilityHint("Manage Kash Files cloud storage")
                        
                        NavigationLink(destination: PodsListView()) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.title3)
                                Text("Manage Pods")
                                    .font(.headline)
                                    .fontWeight(.medium)
                                
                                if !podConfigs.isEmpty {
                                    Spacer()
                                    Text("\(podConfigs.count)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.purple)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white, lineWidth: 1.5)
                            )
                            .cornerRadius(10)
                        }
                        .accessibilityHint("Manage distributed social pods")
                    }

                    // 4. External link buttons
                    VStack(spacing: 16) {
                        Button(action: {
                            #if os(iOS)
                            if let url = URL(string: "https://blog.pulseaiplatform.com") {
                                UIApplication.shared.open(url)
                            }
                            #elseif os(macOS)
                            if let url = URL(string: "https://blog.pulseaiplatform.com") {
                                NSWorkspace.shared.open(url)
                            }
                            #endif
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
                            #if os(iOS)
                            if let url = URL(string: "https://pulseaiplatform.com") {
                                UIApplication.shared.open(url)
                            }
                            #elseif os(macOS)
                            if let url = URL(string: "https://pulseaiplatform.com") {
                                NSWorkspace.shared.open(url)
                            }
                            #endif
                        }) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.title3)
                                Text("Go to Portal")
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
                        .accessibilityHint("Opens Pulse AI Platform portal in browser")
                        
                        Button(action: {
                            if let nodeName = viewModel.currentEndpoint?.nodeName,
                               !nodeName.isEmpty,
                               let url = URL(string: "https://pulse-\(nodeName).xyzpulseinfra.com") {
                                #if os(iOS)
                                UIApplication.shared.open(url)
                                #elseif os(macOS)
                                NSWorkspace.shared.open(url)
                                #endif
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
                #if os(iOS)
                .frame(minHeight: UIScreen.main.bounds.height * 0.8, alignment: .top)
                #endif
                .navigationTitle("Kash Stash")
            }
            .background(Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showQRImport) {
            QRImportView(viewModel: viewModel)
        }
        .sheet(isPresented: $showQRTextCapture) {
            QRTextCaptureView() // ✅ FIXED - No parameters needed
        }
        .onAppear {
            // Load pod configs
            podConfigs = AppConfigStore.load().podConfigs
        }
    }
    
    private var isMyNodeDisabled: Bool {
        viewModel.currentEndpoint?.nodeName.isEmpty ?? true
    }
}
