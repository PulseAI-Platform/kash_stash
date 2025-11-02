import SwiftUI

struct TagSelectionView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @Binding var selectedTags: String
    @Binding var isPresented: Bool
    @State private var customTag: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Manual entry
                HStack {
                    TextField("Add custom tag", text: $customTag)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Add") {
                        if !customTag.isEmpty {
                            addTag(customTag)
                            customTag = ""
                        }
                    }
                    .disabled(customTag.isEmpty)
                }
                .padding()
                
                // Current selection
                if !selectedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(currentTagsArray, id: \.self) { tag in
                                TagChip(tag: tag) {
                                    removeTag(tag)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 50)
                    .background(Color(.systemGray6))
                }
                
                // Recent tags
                List {
                    Section(header: Text("Recent Tags")) {
                        ForEach(viewModel.recentTagsList, id: \.self) { tag in
                            Button(action: {
                                addTag(tag)
                            }) {
                                HStack {
                                    Text(tag)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if currentTagsArray.contains(tag) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Select Tags")
            .navigationBarItems(
                leading: Button("Clear All") {
                    selectedTags = ""
                },
                trailing: Button("Done") {
                    isPresented = false
                }
            )
        }
    }
    
    var currentTagsArray: [String] {
        selectedTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    func addTag(_ tag: String) {
        let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTag.isEmpty && !currentTagsArray.contains(cleanTag) {
            if selectedTags.isEmpty {
                selectedTags = cleanTag
            } else {
                selectedTags += ",\(cleanTag)"
            }
        }
    }
    
    func removeTag(_ tag: String) {
        let tags = currentTagsArray.filter { $0 != tag }
        selectedTags = tags.joined(separator: ",")
    }
}

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(12)
    }
}
