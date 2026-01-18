import SwiftUI

struct PromptSelectionView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @Binding var currentText: String
    @Binding var isPresented: Bool
    @State private var customPrompt: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Manual entry
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create New Prompt")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    HStack(alignment: .top) {
                        TextEditor(text: $customPrompt)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        
                        VStack(spacing: 8) {
                            Button(action: {
                                if !customPrompt.isEmpty {
                                    appendPrompt(customPrompt)
                                    viewModel.addRecentPrompt(customPrompt)
                                    customPrompt = ""
                                }
                            }) {
                                Text("Add")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(customPrompt.isEmpty ? Color.gray : Color.blue)
                                    .cornerRadius(8)
                            }
                            .disabled(customPrompt.isEmpty)
                            
                            Button(action: {
                                if !customPrompt.isEmpty {
                                    viewModel.addRecentPrompt(customPrompt)
                                    customPrompt = ""
                                }
                            }) {
                                Text("Save")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(customPrompt.isEmpty ? Color.gray : Color.green)
                                    .cornerRadius(8)
                            }
                            .disabled(customPrompt.isEmpty)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
                
                Divider()
                
                // Saved prompts list
                List {
                    Section(header: Text("Saved Prompts")) {
                        if viewModel.recentPromptsList.isEmpty {
                            Text("No saved prompts yet")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(viewModel.recentPromptsList, id: \.self) { prompt in
                                Button(action: {
                                    appendPrompt(prompt)
                                    isPresented = false
                                }) {
                                    HStack(alignment: .top) {
                                        Text(prompt)
                                            .foregroundColor(.primary)
                                            .lineLimit(3)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        viewModel.deleteRecentPrompt(prompt)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("AI Prompts")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    isPresented = false
                }
            )
        }
    }
    
    func appendPrompt(_ prompt: String) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPrompt.isEmpty {
            if currentText.isEmpty {
                currentText = cleanPrompt
            } else {
                // Add prompt AFTER existing text with spacing
                currentText += "\n\n" + cleanPrompt
            }
        }
    }
}