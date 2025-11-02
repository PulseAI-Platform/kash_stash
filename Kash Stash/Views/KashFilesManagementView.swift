import SwiftUI

struct KashFilesManagementView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @State private var editingKashFiles: KashFilesConfig?
    @State private var addingNew = false

    var body: some View {
        List {
            Section(header: Text("Kash Files Instances")) {
                if viewModel.config.kashFiles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "icloud.slash")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("No Kash Files configured")
                            .font(.headline)
                        Text("Add a Kash Files instance to enable cloud storage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(viewModel.config.kashFiles) { kf in
                        Button(action: {
                            editingKashFiles = kf
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(kf.name)
                                            .font(.headline)
                                        if kf.isActive {
                                            Text("ACTIVE")
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green)
                                                .foregroundColor(.white)
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text(kf.url)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .swipeActions(allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteKashFiles(kf)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if !kf.isActive {
                                Button {
                                    viewModel.setActiveKashFiles(kf)
                                } label: {
                                    Label("Set Active", systemImage: "checkmark.circle")
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Kash Files")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    addingNew = true
                }) {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingKashFiles) { kashFiles in
            EditKashFilesSheet(
                kashFiles: kashFiles,
                onSave: { kf in
                    viewModel.updateKashFiles(kf)
                    editingKashFiles = nil
                },
                onCancel: {
                    editingKashFiles = nil
                }
            )
        }
        .sheet(isPresented: $addingNew) {
            EditKashFilesSheet(
                kashFiles: nil,
                onSave: { kf in
                    viewModel.addKashFiles(kf)
                    addingNew = false
                },
                onCancel: {
                    addingNew = false
                }
            )
        }
    }
}

struct EditKashFilesSheet: View {
    let kashFiles: KashFilesConfig?
    let onSave: (KashFilesConfig) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var key: String = ""
    
    @Environment(\.presentationMode) var presentationMode
    
    var isEditing: Bool { kashFiles != nil }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Configuration")) {
                    TextField("Instance Name", text: $name)
                    TextField("URL (e.g., https://kf.example.com)", text: $url)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    SecureField("API Key", text: $key)
                }
                
                Section {
                    Button(isEditing ? "Update" : "Add") {
                        if let existing = kashFiles {
                            let updated = KashFilesConfig(
                                id: existing.id,
                                name: name,
                                url: url,
                                key: key,
                                isActive: existing.isActive
                            )
                            onSave(updated)
                        } else {
                            let newKF = KashFilesConfig(
                                id: UUID(),
                                name: name,
                                url: url,
                                key: key,
                                isActive: false
                            )
                            onSave(newKF)
                        }
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(name.isEmpty || url.isEmpty || key.isEmpty)
                }
            }
            .navigationTitle(isEditing ? "Edit Kash Files" : "Add Kash Files")
            .navigationBarItems(trailing: Button("Cancel") {
                onCancel()
                presentationMode.wrappedValue.dismiss()
            })
        }
        .onAppear {
            if let kf = kashFiles {
                name = kf.name
                url = kf.url
                key = kf.key
            }
        }
    }
}
