//
//  FilterHeaderView.swift
//  Kash Stash
//

import SwiftUI

struct FilterHeaderView: View {
    @Binding var showFilters: Bool
    @Binding var searchText: String
    @Binding var selectedTags: Set<String>
    let availableTags: Set<String>
    @Binding var selectedNodes: Set<String>
    let availableNodes: Set<String>
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    let advertisedTags: Set<String>
    let discoveredTags: Set<String>
    
    init(showFilters: Binding<Bool>,
         searchText: Binding<String>,
         selectedTags: Binding<Set<String>>,
         availableTags: Set<String>,
         selectedNodes: Binding<Set<String>>,
         availableNodes: Set<String>,
         startDate: Binding<Date?>,
         endDate: Binding<Date?>,
         advertisedTags: Set<String>? = nil,
         discoveredTags: Set<String>? = nil) {
        self._showFilters = showFilters
        self._searchText = searchText
        self._selectedTags = selectedTags
        self.availableTags = availableTags
        self._selectedNodes = selectedNodes
        self.availableNodes = availableNodes
        self._startDate = startDate
        self._endDate = endDate
        self.advertisedTags = advertisedTags ?? availableTags
        self.discoveredTags = discoveredTags ?? []
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Always visible search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search digests...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: { showFilters.toggle() }) {
                    Image(systemName: showFilters ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            
            // Collapsible filter section
            if showFilters {
                VStack(spacing: 10) {
                    // Date range
                    DateRangePicker(startDate: $startDate, endDate: $endDate)
                    
                    // Tag selector with advertised/discovered distinction
                    TagMultiSelector(
                        selectedTags: $selectedTags,
                        availableTags: availableTags,
                        advertisedTags: advertisedTags,
                        discoveredTags: discoveredTags
                    )
                    
                    // Node selector
                    NodeMultiSelector(
                        selectedNodes: $selectedNodes,
                        availableNodes: availableNodes
                    )
                }
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

// Supporting components
struct DateRangePicker: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @State private var showStartPicker = false
    @State private var showEndPicker = false
    
    var body: some View {
        HStack {
            // Start date
            VStack(alignment: .leading, spacing: 4) {
                Text("From")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: { showStartPicker.toggle() }) {
                    Text(startDate != nil ? formatDate(startDate!) : "Any time")
                        .font(.subheadline)
                        .foregroundColor(startDate != nil ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
            
            // End date
            VStack(alignment: .leading, spacing: 4) {
                Text("To")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: { showEndPicker.toggle() }) {
                    Text(endDate != nil ? formatDate(endDate!) : "Now")
                        .font(.subheadline)
                        .foregroundColor(endDate != nil ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
        }
        .sheet(isPresented: $showStartPicker) {
            DatePickerSheet(date: $startDate, title: "Start Date")
        }
        .sheet(isPresented: $showEndPicker) {
            DatePickerSheet(date: $endDate, title: "End Date")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct DatePickerSheet: View {
    @Binding var date: Date?
    let title: String
    @Environment(\.dismiss) var dismiss
    @State private var tempDate = Date()
    
    var body: some View {
        NavigationView {
            VStack {
                DatePicker(title, selection: $tempDate, displayedComponents: .date)
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .padding()
                
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        date = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        date = tempDate
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TagMultiSelector: View {
    @Binding var selectedTags: Set<String>
    let availableTags: Set<String>
    let advertisedTags: Set<String>
    let discoveredTags: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tags")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !discoveredTags.isEmpty {
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.purple)
                            Text("Advertised")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 2) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text("Discovered")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Show advertised tags first with a special indicator
                    ForEach(Array(advertisedTags).sorted(), id: \.self) { tag in
                        TagToggle(
                            tag: tag,
                            isSelected: selectedTags.contains(tag),
                            isAdvertised: true,
                            action: {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }
                        )
                    }
                    
                    // Then show discovered tags (excluding ones already shown as advertised)
                    ForEach(Array(discoveredTags.subtracting(advertisedTags)).sorted(), id: \.self) { tag in
                        TagToggle(
                            tag: tag,
                            isSelected: selectedTags.contains(tag),
                            isAdvertised: false,
                            action: {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

struct TagToggle: View {
    let tag: String
    let isSelected: Bool
    let isAdvertised: Bool
    let action: () -> Void
    
    init(tag: String, isSelected: Bool, isAdvertised: Bool = false, action: @escaping () -> Void) {
        self.tag = tag
        self.isSelected = isSelected
        self.isAdvertised = isAdvertised
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isAdvertised {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white : .purple)
                } else {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white : .blue)
                }
                
                Text("#\(tag)")
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

struct NodeMultiSelector: View {
    @Binding var selectedNodes: Set<String>
    let availableNodes: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nodes")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(availableNodes).sorted(), id: \.self) { node in
                        NodeToggle(
                            node: node,
                            isSelected: selectedNodes.contains(node),
                            action: {
                                if selectedNodes.contains(node) {
                                    selectedNodes.remove(node)
                                } else {
                                    selectedNodes.insert(node)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

struct NodeToggle: View {
    let node: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label(node, systemImage: "server.rack")
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}
