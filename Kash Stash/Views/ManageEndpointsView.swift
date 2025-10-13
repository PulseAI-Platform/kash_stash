import SwiftUI

struct ManageEndpointsView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @State private var editingEndpoint: KashStashEndpoint?
    @State private var addingNew = false

    var body: some View {
        List {
            Section(header: Text("Endpoints")) {
                ForEach(viewModel.config.endpoints) { ep in
                    Button(action: {
                        editingEndpoint = ep
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ep.name).bold()
                                if !ep.device.isEmpty {
                                    Text(ep.device).font(.caption).foregroundColor(.secondary)
                                }
                                Text(ep.nodeName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if viewModel.config.lastUsedEndpoint == ep.id {
                                Text("Current")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .swipeActions(allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteEndpoint(ep)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            viewModel.setCurrentEndpoint(ep)
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                        .tint(.accentColor)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Manage Endpoints")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    addingNew = true
                }) {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editingEndpoint) { endpoint in
            EditEndpointSheet(
                endpoint: endpoint,
                onSave: { ep in
                    viewModel.updateEndpoint(ep)
                    editingEndpoint = nil
                },
                onCancel: { editingEndpoint = nil }
            )
        }
        .sheet(isPresented: $addingNew) {
            EditEndpointSheet(
                endpoint: nil,
                onSave: { ep in
                    viewModel.addEndpoint(ep)
                    addingNew = false
                },
                onCancel: { addingNew = false }
            )
        }
    }
}
