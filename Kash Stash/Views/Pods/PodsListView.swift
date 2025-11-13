//
//  PodsListView.swift
//  Kash Stash
//
//  Created by Matt on 11/11/25.
//

import SwiftUI
import AVFoundation

struct PodsListView: View {
    @State private var podConfigs: [PodConfig] = []
    @State private var showAddPodQR = false
    @State private var showManualAddPod = false
    @State private var podToEdit: PodConfig?
    @State private var isRefreshing = false
    @State private var podToShare: PodConfig?
    
    var body: some View {
        List {
            if podConfigs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 60))
                        .foregroundColor(.purple.opacity(0.5))
                    
                    Text("No Pods Configured")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Scan a pod QR code to join your first distributed social network")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button(action: { showAddPodQR = true }) {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color.purple)
                            .cornerRadius(10)
                    }
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, minHeight: 400)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } else {
                Section {
                    ForEach(podConfigs) { pod in
                        NavigationLink(destination: PodFeedView(pod: pod)) {
                            PodRow(pod: pod)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contextMenu {
                            Button(action: { podToShare = pod }) {
                                Label("Share QR Code", systemImage: "qrcode")
                            }
                            
                            Button(action: { podToEdit = pod }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            
                            Button(action: { togglePodActive(pod) }) {
                                Label(
                                    pod.isActive ? "Deactivate" : "Activate",
                                    systemImage: pod.isActive ? "pause.circle" : "play.circle"
                                )
                            }
                            
                            Button(action: {
                                Task {
                                    await refreshPod(pod)
                                    loadPods()
                                }
                            }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive, action: { deletePod(pod) }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive, action: { deletePod(pod) }) {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button(action: { podToEdit = pod }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            Button(action: { togglePodActive(pod) }) {
                                Label(
                                    pod.isActive ? "Deactivate" : "Activate",
                                    systemImage: pod.isActive ? "pause.circle" : "play.circle"
                                )
                            }
                            .tint(pod.isActive ? .gray : .green)
                        }
                    }
                    .onDelete(perform: deletePods)
                } header: {
                    Text("\(podConfigs.count) Pod\(podConfigs.count == 1 ? "" : "s")")
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Pods")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showAddPodQR = true }) {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                    
                    Button(action: { showManualAddPod = true }) {
                        Label("Add Manually", systemImage: "plus.circle")
                    }
                    
                    if !podConfigs.isEmpty {
                        Divider()
                        
                        Button(action: refreshAllPods) {
                            Label("Refresh All", systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPodQR) {
            PodQRScannerView { scannedPod in
                addPod(scannedPod)
                showAddPodQR = false
            }
        }
        .sheet(isPresented: $showManualAddPod) {
            ManualPodAddView { newPod in
                addPod(newPod)
                showManualAddPod = false
            }
        }
        .sheet(item: $podToEdit) { pod in
            EditPodView(pod: pod) { updatedPod in
                updatePod(updatedPod)
                podToEdit = nil
            }
        }
        .sheet(item: $podToShare) { pod in
            PodQRShareView(pod: pod)
        }
        .onAppear {
            loadPods()
        }
        .refreshable {
            await refreshAllPodsAsync()
        }
    }
    
    private func loadPods() {
        podConfigs = AppConfigStore.load().podConfigs
    }
    
    private func addPod(_ pod: PodConfig) {
        podConfigs.append(pod)
        AppConfigStore.addPodConfig(pod)
        
        // Auto-refresh to get nodes and tags
        Task {
            await refreshPod(pod)
            loadPods()
        }
    }
    
    private func updatePod(_ pod: PodConfig) {
        AppConfigStore.updatePodConfig(pod)
        loadPods()
    }
    
    private func togglePodActive(_ pod: PodConfig) {
        var updatedPod = pod
        updatedPod.isActive.toggle()
        AppConfigStore.updatePodConfig(updatedPod)
        loadPods()
    }
    
    private func deletePod(_ pod: PodConfig) {
        AppConfigStore.removePodConfig(id: pod.id)
        loadPods()
    }
    
    private func deletePods(at offsets: IndexSet) {
        for index in offsets {
            let pod = podConfigs[index]
            AppConfigStore.removePodConfig(id: pod.id)
        }
        podConfigs.remove(atOffsets: offsets)
    }
    
    private func refreshAllPods() {
        Task {
            await refreshAllPodsAsync()
        }
    }
    
    private func refreshAllPodsAsync() async {
        isRefreshing = true
        
        for pod in podConfigs {
            await refreshPod(pod)
        }
        
        // Reload to show updated data
        loadPods()
        isRefreshing = false
    }
    
    private func refreshPod(_ pod: PodConfig) async {
        do {
            let podClient = PodClient()
            let nodes = try await podClient.discoverNodes(pod: pod)
            
            // Get all unique tags from all nodes
            let allTags = Set(nodes.flatMap { $0.advertisedTags })
            
            AppConfigStore.refreshPodCache(
                podId: pod.id,
                nodes: nodes,
                tags: Array(allTags)
            )
        } catch {
            print("Failed to refresh pod \(pod.name): \(error)")
        }
    }
}

// Keep the PodRow view as is
struct PodRow: View {
    let pod: PodConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pod.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(pod.entranceNodeUrl)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if pod.isActive {
                        Text("ACTIVE")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    } else {
                        Text("INACTIVE")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    
                    if pod.discoveredNodes.count > 0 {
                        Text("\(pod.discoveredNodes.count) node\(pod.discoveredNodes.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Tags
            if !pod.cachedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(pod.cachedTags.prefix(5), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15))
                                .foregroundColor(.purple)
                                .cornerRadius(4)
                        }
                        
                        if pod.cachedTags.count > 5 {
                            Text("+\(pod.cachedTags.count - 5) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Last refresh
            if let lastRefresh = pod.lastRefresh {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Updated \(lastRefresh, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// Keep all the other supporting views (EditPodView, ManualPodAddView, FlowLayout, PodQRScannerView) exactly as they are...

// Edit Pod View
struct EditPodView: View {
    @Environment(\.dismiss) var dismiss
    let pod: PodConfig
    @State private var name: String
    @State private var entranceUrl: String
    @State private var presharedKey: String
    @State private var isActive: Bool
    @State private var showKey = false
    
    let onSave: (PodConfig) -> Void
    
    init(pod: PodConfig, onSave: @escaping (PodConfig) -> Void) {
        self.pod = pod
        self.onSave = onSave
        _name = State(initialValue: pod.name)
        _entranceUrl = State(initialValue: pod.entranceNodeUrl)
        _presharedKey = State(initialValue: pod.presharedKey)
        _isActive = State(initialValue: pod.isActive)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Pod Information")) {
                    TextField("Pod Name", text: $name)
                        .autocapitalization(.none)
                    
                    TextField("Entrance Node URL", text: $entranceUrl)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    HStack {
                        if showKey {
                            TextField("Preshared Key", text: $presharedKey)
                                .autocapitalization(.none)
                        } else {
                            SecureField("Preshared Key", text: $presharedKey)
                                .autocapitalization(.none)
                        }
                        
                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Settings")) {
                    Toggle("Active", isOn: $isActive)
                }
                
                if !pod.discoveredNodes.isEmpty {
                    Section(header: Text("Discovered Nodes (\(pod.discoveredNodes.count))")) {
                        ForEach(pod.discoveredNodes) { node in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.name)
                                    .font(.subheadline)
                                Text(node.nodeUrl)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                if !pod.cachedTags.isEmpty {
                    Section(header: Text("Available Tags")) {
                        ScrollView {
                            FlowLayout(spacing: 8) {
                                ForEach(pod.cachedTags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.purple.opacity(0.15))
                                        .foregroundColor(.purple)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Pod")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updatedPod = pod
                        updatedPod.name = name
                        updatedPod.entranceNodeUrl = entranceUrl
                        updatedPod.presharedKey = presharedKey
                        updatedPod.isActive = isActive
                        onSave(updatedPod)
                    }
                    .disabled(name.isEmpty || entranceUrl.isEmpty || presharedKey.isEmpty)
                }
            }
        }
    }
}

// Manual Pod Add View
struct ManualPodAddView: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var entranceUrl = ""
    @State private var presharedKey = ""
    @State private var showKey = false
    
    let onAdd: (PodConfig) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Pod Information")) {
                    TextField("Pod Name", text: $name)
                        .autocapitalization(.none)
                    
                    TextField("Entrance Node URL", text: $entranceUrl)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    HStack {
                        if showKey {
                            TextField("Preshared Key", text: $presharedKey)
                                .autocapitalization(.none)
                        } else {
                            SecureField("Preshared Key", text: $presharedKey)
                                .autocapitalization(.none)
                        }
                        
                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Text("Contact your pod administrator for these details, or scan their QR code instead.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Pod Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let newPod = PodConfig(
                            name: name,
                            entranceNodeUrl: entranceUrl,
                            presharedKey: presharedKey
                        )
                        onAdd(newPod)
                    }
                    .disabled(name.isEmpty || entranceUrl.isEmpty || presharedKey.isEmpty)
                }
            }
        }
    }
}


// Pod QR Scanner View
struct PodQRScannerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showError = false
    @State private var errorMessage = ""
    
    let onScan: (PodConfig) -> Void
    
    var body: some View {
        QRCodeScannerView { code in
            processScanResult(code)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func processScanResult(_ result: String) {
        let parsed = QRCodeScanner.parseQRConfig(result)
        
        switch parsed {
        case .pod(let podConfig):
            dismiss()
            onScan(podConfig)
            
        case .endpoint(_), .kashFiles(_):
            errorMessage = "This QR code is for an endpoint or Kash Files configuration. Please use the main QR import feature instead."
            showError = true
            
        case .unknown(_), .invalid:
            errorMessage = "This QR code is not a valid Pod invitation"
            showError = true
        }
    }
}

// Preview
struct PodsListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PodsListView()
        }
    }
}
// Add this at the bottom of PodsListView.swift

// Flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: result.positions[index].x + bounds.minX,
                                      y: result.positions[index].y + bounds.minY),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            
            for subview in subviews {
                let dimensions = subview.sizeThatFits(.unspecified)
                
                if x + dimensions.width > maxWidth, x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, dimensions.height)
                x += dimensions.width + spacing
            }
            
            size = CGSize(width: maxWidth, height: y + maxHeight)
        }
    }
}
