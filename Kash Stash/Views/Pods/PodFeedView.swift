//
//  PodFeedView.swift
//  Kash Stash
//
//  Created by Matt on 11/11/25.
//

import SwiftUI

enum SortOption: String, CaseIterable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case mostReplies = "Most Replies"
    case recentlyActive = "Recently Active"
    
    var systemImage: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        case .mostReplies: return "bubble.left.and.bubble.right"
        case .recentlyActive: return "clock"
        }
    }
}

enum DateRangeOption: String, CaseIterable {
    case allTime = "All Time"
    case today = "Today"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case last90Days = "Last 90 Days"
    case custom = "Custom Range"
    
    var dateRange: (start: Date?, end: Date?) {
        let now = Date()
        let calendar = Calendar.current
        
        switch self {
        case .allTime:
            return (nil, nil)
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -7, to: now)
            return (start, now)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)
            return (start, now)
        case .last90Days:
            let start = calendar.date(byAdding: .day, value: -90, to: now)
            return (start, now)
        case .custom:
            return (nil, nil) // Will be handled separately
        }
    }
}

struct PodFeedView: View {
    let pod: PodConfig
    
    @State private var showNotificationSettings = false
    @State private var showPodInfo = false
    @State private var mutablePod: PodConfig = PodConfig(name: "", entranceNodeUrl: "", presharedKey: "")
    @State private var digests: [Digest] = []
    @State private var isLoading = false
    @State private var selectedTags: Set<String> = []
    @State private var showTagFilter = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var replyingToDigest: Digest? = nil
    @State private var searchText = ""
    @State private var sortOption: SortOption = .newestFirst
    @State private var allDiscoveredTags: [String] = []
    @State private var dateRangeOption: DateRangeOption = .last30Days
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showDatePicker = false
    @State private var tagSearchText = ""
    @State private var selectedThreadDigest: Digest? = nil
    
    var availableTags: [String] {
        let podTags = Set(pod.cachedTags)
        let discoveredFromPod = Set(pod.discoveredTags)
        let digestTags = Set(digests.flatMap { $0.tags })
        let allTags = podTags.union(discoveredFromPod).union(digestTags)
        return Array(allTags).sorted()
    }
    
    var filteredAndSortedDigests: [Digest] {
        var filtered = digests
        
        // FILTER OUT REPLIES - only show top-level posts
        filtered = filtered.filter { digest in
            // Check if it has a repliesTo field set
            if digest.repliesTo != nil {
                return false
            }
            
            // Check if content starts with @ mention (reply format)
            if digest.content.hasPrefix("@") && digest.content.contains(".") {
                return false
            }
            
            // Check for reply tag
            if digest.tags.contains("reply") {
                return false
            }
            
            return true
        }
        
        // Filter by selected tags
        if !selectedTags.isEmpty {
            filtered = filtered.filter { digest in
                !Set(digest.tags).isDisjoint(with: selectedTags)
            }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { digest in
                digest.title.localizedCaseInsensitiveContains(searchText) ||
                digest.content.localizedCaseInsensitiveContains(searchText) ||
                digest.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        // Apply sorting
        switch sortOption {
        case .newestFirst:
            filtered.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            filtered.sort { $0.createdAt < $1.createdAt }
        case .mostReplies:
            let replyCount = { (digest: Digest) -> Int in
                digests.filter { $0.repliesTo == digest.id }.count
            }
            filtered.sort { replyCount($0) > replyCount($1) }
        case .recentlyActive:
            let latestActivity = { (digest: Digest) -> Date in
                let replies = digests.filter { $0.repliesTo == digest.id }
                let latestReplyDate = replies.map { $0.createdAt }.max() ?? digest.createdAt
                return max(digest.createdAt, latestReplyDate)
            }
            filtered.sort { latestActivity($0) > latestActivity($1) }
        }
        
        return filtered
    }
    
    var body: some View {
        mainContent
            .navigationTitle(pod.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    toolbarMenu
                }
            }
            .refreshable {
                await loadDigestsAsync()
            }
            .sheet(item: $replyingToDigest) { digest in
                ReplyPostView(replyingTo: digest, pod: pod)
                    .onDisappear {
                        loadDigests()
                    }
            }
            .sheet(item: $selectedThreadDigest) { digest in
                ThreadView(
                    originalDigest: digest,
                    allDigests: digests,
                    pod: pod
                )
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
            .sheet(isPresented: $showNotificationSettings) {
                NavigationView {
                    PodNotificationSettings(pod: $mutablePod)
                }
            }
            .sheet(isPresented: $showPodInfo) {
                podInfoSheet
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .onAppear {
                mutablePod = pod
                if digests.isEmpty {
                    loadDigests()
                }
            }
            .onDisappear {
                // Save pod changes
                if mutablePod.id == pod.id {
                    AppConfigStore.updatePodConfig(mutablePod)
                }
            }
    }
    
    // MARK: - View Components
    
    private var mainContent: some View {
        ZStack {
            if isLoading && digests.isEmpty {
                loadingView
            } else if digests.isEmpty && !isLoading {
                emptyStateView
            } else {
                contentListView
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading digests...")
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Digests Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("This pod doesn't have any posts yet, or try a different date range.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: { loadDigests() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(Color.purple)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
    
    private var contentListView: some View {
        List {
            dateRangeSection
            sortingSection
            
            if !availableTags.isEmpty {
                tagFilterSection
            }
            
            digestListSection
        }
        .listStyle(InsetGroupedListStyle())
        .searchable(text: $searchText, prompt: "Search digests...")
    }
    
    private var dateRangeSection: some View {
        Section {
            Menu {
                ForEach(DateRangeOption.allCases, id: \.self) { option in
                    Button(action: {
                        dateRangeOption = option
                        if option == .custom {
                            showDatePicker = true
                        } else {
                            loadDigests()
                        }
                    }) {
                        Label(option.rawValue, systemImage: "calendar")
                            .foregroundColor(dateRangeOption == option ? .accentColor : .primary)
                    }
                }
            } label: {
                HStack {
                    Label("Date Range: \(dateRangeOption.rawValue)", systemImage: "calendar")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var sortingSection: some View {
        Section {
            Menu {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button(action: { sortOption = option }) {
                        Label(option.rawValue, systemImage: option.systemImage)
                            .foregroundColor(sortOption == option ? .accentColor : .primary)
                    }
                }
            } label: {
                HStack {
                    Label("Sort: \(sortOption.rawValue)", systemImage: sortOption.systemImage)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var tagFilterSection: some View {
        Section {
            Button(action: { withAnimation { showTagFilter.toggle() } }) {
                HStack {
                    Label("Filter by Tags", systemImage: "tag")
                    Spacer()
                    if !selectedTags.isEmpty {
                        Text("\(selectedTags.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: showTagFilter ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if showTagFilter {
                tagFilterContent
            }
        }
    }
    
    @ViewBuilder
    private var tagFilterContent: some View {
        // Tag search bar
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)
            
            TextField("Search tags...", text: $tagSearchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.body)
            
            if !tagSearchText.isEmpty {
                Button(action: { tagSearchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        
        let filteredTags = tagSearchText.isEmpty
            ? availableTags
            : availableTags.filter {
                $0.localizedCaseInsensitiveContains(tagSearchText)
            }
        
        if filteredTags.isEmpty && !tagSearchText.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("No tags matching '\(tagSearchText)'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
                Spacer()
            }
        } else {
            tagChipScrollView(filteredTags: filteredTags)
        }
    }
    
    private func tagChipScrollView(filteredTags: [String]) -> some View {
        VStack {
            ScrollView {
                // Simple wrapping view instead of FlowLayout
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<((filteredTags.count + 2) / 3), id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { col in
                                let index = row * 3 + col
                                if index < filteredTags.count {
                                    let tag = filteredTags.sorted()[index]
                                    TagFilterChip(
                                        tag: tag,
                                        isSelected: selectedTags.contains(tag),
                                        onTap: {
                                            toggleTagFilter(tag)
                                        }
                                    )
                                    .overlay(
                                        Group {
                                            if !pod.cachedTags.contains(tag) {
                                                Circle()
                                                    .fill(Color.blue)
                                                    .frame(width: 8, height: 8)
                                                    .offset(x: -4, y: -4)
                                            }
                                        },
                                        alignment: .topTrailing
                                    )
                                } else {
                                    Spacer()
                                        .frame(height: 0)
                                }
                            }
                        }
                    }
                }
                .padding(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            .frame(maxHeight: 200)
            
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text("Discovered")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !selectedTags.isEmpty {
                    Button(action: {
                        selectedTags.removeAll()
                        tagSearchText = ""
                    }) {
                        Text("Clear all")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                Text("\(filteredTags.count) of \(availableTags.count) tags")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4))
        }
    }
    
    private var digestListSection: some View {
        Section {
            if filteredAndSortedDigests.isEmpty && !digests.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No digests match your filters")
                        .foregroundColor(.secondary)
                    Button("Clear Filters") {
                        selectedTags.removeAll()
                        searchText = ""
                    }
                    .foregroundColor(.blue)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(filteredAndSortedDigests) { digest in
                    EnhancedDigestCard(
                        digest: digest,
                        replyCount: digests.filter { $0.repliesTo == digest.id }.count,
                        onTap: {
                            selectedThreadDigest = digest
                        },
                        onReply: {
                            replyingToDigest = digest
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        } header: {
            HStack {
                Text("\(filteredAndSortedDigests.count) Digest\(filteredAndSortedDigests.count == 1 ? "" : "s")")
                if filteredAndSortedDigests.count != digests.count {
                    Text("(\(digests.count) total)")
                        .foregroundColor(.secondary)
                }
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
    }
    
    private var toolbarMenu: some View {
        Menu {
            Button(action: { loadDigests() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
            
            if !selectedTags.isEmpty {
                Button(action: { selectedTags.removeAll() }) {
                    Label("Clear Tag Filters", systemImage: "xmark.circle")
                }
            }
            
            Divider()
            
            Menu {
                ForEach(DateRangeOption.allCases, id: \.self) { option in
                    Button(action: {
                        dateRangeOption = option
                        if option == .custom {
                            showDatePicker = true
                        } else {
                            loadDigests()
                        }
                    }) {
                        HStack {
                            Text(option.rawValue)
                            if dateRangeOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Date Range", systemImage: "calendar")
            }
            
            Divider()
            
            Button(action: { showNotificationSettings = true }) {
                Label("Notification Settings", systemImage: "bell")
            }
            
            Button(action: { showPodInfo = true }) {
                Label("Pod Info", systemImage: "info.circle")
            }
            
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    private var datePickerSheet: some View {
        NavigationView {
            Form {
                DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
            }
            .navigationTitle("Custom Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showDatePicker = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        showDatePicker = false
                        loadDigests()
                    }
                }
            }
        }
    }
    
    private var podInfoSheet: some View {
        NavigationView {
            Form {
                Section("Pod Details") {
                    LabeledContent("Name", value: pod.name)
                    LabeledContent("Entrance URL", value: pod.entranceNodeUrl)
                    LabeledContent("Tags", value: pod.cachedTags.joined(separator: ", "))
                    LabeledContent("Nodes", value: "\(pod.discoveredNodes.count)")
                }
            }
            .navigationTitle("Pod Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showPodInfo = false
                    }
                }
            }
        }
    }
    
    // MARK: - Methods
    
    private func toggleTagFilter(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
    
    private func loadDigests() {
        Task {
            await loadDigestsAsync()
        }
    }
    
    private func loadDigestsAsync() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let podClient = PodClient()
            var allDigests: [Digest] = []
            var discoveredTagsSet = Set<String>()
            
            let dateRange: (start: Date?, end: Date?)
            if dateRangeOption == .custom {
                dateRange = (customStartDate, customEndDate)
            } else {
                dateRange = dateRangeOption.dateRange
            }
            
            let nodesToQuery: [PodNode]
            if pod.discoveredNodes.isEmpty {
                do {
                    let discoveredNodes = try await podClient.discoverNodes(pod: pod)
                    nodesToQuery = discoveredNodes
                    AppConfigStore.refreshPodCache(
                        podId: pod.id,
                        nodes: discoveredNodes,
                        tags: pod.cachedTags
                    )
                } catch {
                    nodesToQuery = [
                        PodNode(
                            nodeUrl: pod.entranceNodeUrl,
                            name: "Entrance Node",
                            advertisedTags: [],
                            status: "active",
                            lastSeen: Date()
                        )
                    ]
                }
            } else {
                nodesToQuery = pod.discoveredNodes
            }
            
            for node in nodesToQuery {
                do {
                    let tagsToFetch: [String]
                    if !selectedTags.isEmpty {
                        tagsToFetch = Array(selectedTags)
                    } else if !pod.cachedTags.isEmpty {
                        tagsToFetch = pod.cachedTags
                    } else if !node.advertisedTags.isEmpty {
                        tagsToFetch = node.advertisedTags
                    } else {
                        tagsToFetch = ["*"]
                    }
                    
                    print("[PodFeedView] Fetching from \(node.name) with tags: \(tagsToFetch)")
                    
                    var currentPage = 1
                    var hasMorePages = true
                    
                    while hasMorePages {
                        let response = try await podClient.fetchDigests(
                            from: node,
                            tags: tagsToFetch,
                            podKey: pod.presharedKey,
                            page: currentPage,
                            perPage: 100,
                            startDate: dateRange.start,
                            endDate: dateRange.end
                        )
                        if let firstEntry = response.feedentries.first {
                            print("  ID: \(firstEntry.id)")
                            print("  Created At: \(firstEntry.createdAt ?? "nil")")
                            print("  Title: \(firstEntry.title ?? "nil")")
                        }
                        let digestsFromPage = response.feedentries.compactMap { entry -> Digest? in
                            var createdDate = Date()
                            
                            print("[Date Debug] Entry ID: \(entry.id)")
                            print("[Date Debug] Raw createdAt from API: \(entry.createdAt ?? "NIL")")
                            
                            if let dateString = entry.createdAt {
                                // First, let's see if the string is empty or weird
                                if dateString.isEmpty {
                                    print("[Date Debug] ERROR: Date string is empty!")
                                    createdDate = Date()
                                } else {
                                    let isoFormatter = ISO8601DateFormatter()
                                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                    
                                    if let parsedDate = isoFormatter.date(from: dateString) {
                                        createdDate = parsedDate
                                        print("[Date Debug] ✓ Successfully parsed: \(dateString) -> \(createdDate)")
                                    } else {
                                        // Try without fractional seconds
                                        isoFormatter.formatOptions = [.withInternetDateTime]
                                        if let parsedDate = isoFormatter.date(from: dateString) {
                                            createdDate = parsedDate
                                            print("[Date Debug] ✓ Successfully parsed (no fractions): \(dateString) -> \(createdDate)")
                                        } else {
                                            // Try manual parsing
                                            let formatter = DateFormatter()
                                            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                                            formatter.locale = Locale(identifier: "en_US_POSIX")
                                            formatter.timeZone = TimeZone(secondsFromGMT: 0)
                                            
                                            if let parsedDate = formatter.date(from: dateString) {
                                                createdDate = parsedDate
                                                print("[Date Debug] ✓ Successfully parsed with manual formatter: \(dateString) -> \(createdDate)")
                                            } else {
                                                print("[Date Debug] ✗ FAILED to parse date, using current date as fallback")
                                                print("[Date Debug]   Problematic string: '\(dateString)'")
                                                createdDate = Date()
                                            }
                                        }
                                    }
                                }
                            } else {
                                print("[Date Debug] ✗ createdAt is nil from API!")
                            }
                            
                            print("[Date Debug] Final date being used: \(createdDate)")
                            print("[Date Debug] ---")
                            
                            let tagNames = entry.tags?.map { $0.name } ?? []
                            discoveredTagsSet.formUnion(tagNames)
                            
                            // Parse replies
                            var repliesTo: String? = nil
                            if let content = entry.content {
                                if content.contains("@reply:") {
                                    if let range = content.range(of: "@reply:") {
                                        let afterReply = content[range.upperBound...]
                                        if let spaceIndex = afterReply.firstIndex(of: " ") {
                                            repliesTo = String(afterReply[..<spaceIndex])
                                        } else {
                                            repliesTo = String(afterReply)
                                        }
                                    }
                                } else if content.hasPrefix("@") {
                                    if let spaceIndex = content.firstIndex(of: " ") {
                                        let mention = content[content.index(after: content.startIndex)..<spaceIndex]
                                        let parts = mention.split(separator: ".")
                                        
                                        if parts.count >= 5 {
                                            let digestIdIndex = parts.count - 2
                                            let potentialDigestId = String(parts[digestIdIndex])
                                            if !potentialDigestId.isEmpty {
                                                repliesTo = potentialDigestId
                                            }
                                        }
                                    }
                                }
                            }
                            
                            return Digest(
                                id: String(entry.id),
                                title: entry.title?.isEmpty == false ? entry.title! : "",
                                content: entry.content ?? "",
                                tags: tagNames,
                                sourceNode: node.name,
                                createdAt: createdDate,
                                inPods: [pod.name],
                                isMyPost: false,
                                isReplyToMe: false,
                                repliesTo: repliesTo
                            )
                        }
                        
                        allDigests.append(contentsOf: digestsFromPage)
                        hasMorePages = currentPage < response.pages
                        currentPage += 1
                    }
                } catch {
                    print("Failed to fetch from node \(node.name): \(error)")
                }
            }
            
            if !discoveredTagsSet.isEmpty {
                AppConfigStore.updateDiscoveredTags(podId: pod.id, tags: Array(discoveredTagsSet))
            }
            
            var digestDict: [String: Digest] = [:]
            for digest in allDigests {
                if var existing = digestDict[digest.id] {
                    var podSet = existing.inPodsSet
                    podSet.formUnion(digest.inPodsSet)
                    existing.inPods = Array(podSet)
                    digestDict[digest.id] = existing
                } else {
                    digestDict[digest.id] = digest
                }
            }
            
            await MainActor.run {
                self.digests = Array(digestDict.values)
                self.allDiscoveredTags = Array(discoveredTagsSet)
                self.isLoading = false
                
                let config = AppConfigStore.load()
                if let endpoint = config.endpoints.first {
                    NotificationManager.shared.checkForNewContent(
                        in: self.digests,
                        for: pod,
                        deviceName: endpoint.device
                    )
                }
            }
            
            print("[PodFeedView] Total digests loaded: \(digests.count)")
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isLoading = false
            }
        }
    }
}

// Tag filter chip component
struct TagFilterChip: View {
    let tag: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text("#\(tag)")
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.purple : Color.secondary.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Preview
struct PodFeedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PodFeedView(pod: PodConfig(
                name: "Test Pod",
                entranceNodeUrl: "https://example.com",
                presharedKey: "test-key"
            ))
        }
    }
}
