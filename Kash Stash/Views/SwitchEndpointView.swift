import SwiftUI

struct SwitchEndpointView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        List {
            ForEach(viewModel.config.endpoints) { ep in
                HStack {
                    VStack(alignment: .leading) {
                        Text(ep.name).bold()
                        if !ep.device.isEmpty {
                            Text(ep.device).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if viewModel.config.lastUsedEndpoint == ep.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.setCurrentEndpoint(ep)
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .navigationTitle("Switch Endpoint")
    }
}

