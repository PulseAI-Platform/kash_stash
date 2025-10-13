import SwiftUI

struct EditEndpointSheet: View {
    @Environment(\.presentationMode) var presentationMode
    @State var endpoint: KashStashEndpoint
    let onSave: (KashStashEndpoint) -> Void
    let onCancel: () -> Void

    init(endpoint: KashStashEndpoint?, onSave: @escaping (KashStashEndpoint) -> Void, onCancel: @escaping () -> Void) {
        if let ep = endpoint {
            _endpoint = State(initialValue: ep)
        } else {
            _endpoint = State(initialValue: KashStashEndpoint(
                id: UUID(),
                name: "",
                device: "",
                probeKey: "",
                nodeName: "",
                probeId: "",
                keepScreenshots: false
            ))
        }
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Display Info")) {
                    TextField("Name", text: $endpoint.name)
                    TextField("Device name/ID", text: $endpoint.device)
                }
                Section(header: Text("Pulse AI Endpoint")) {
                    TextField("Node name", text: $endpoint.nodeName)
                    SecureField("PROBE_KEY", text: $endpoint.probeKey)
                    TextField("PROBE_ID", text: $endpoint.probeId)
                        .keyboardType(.numbersAndPunctuation)
                }
                Section {
                    Toggle("Keep screenshots in Photos app", isOn: $endpoint.keepScreenshots)
                }
            }
            .navigationTitle(endpoint.name.isEmpty ? "Add Endpoint" : "Edit Endpoint")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(endpoint)
                    }
                    .disabled(endpoint.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || endpoint.nodeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || endpoint.probeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || endpoint.probeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
