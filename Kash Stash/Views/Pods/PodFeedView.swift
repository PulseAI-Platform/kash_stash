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
        
        // First, separate root posts from replies
        let replies = filtered.filter { $0.repliesTo != nil }
        let rootPosts = filtered.filter { $0.repliesTo == nil }
        
        // Build a dictionary of replies by parent ID
        var repliesByParent: [String: [Digest]] = [:]
        for reply in replies {
            if let parentId = reply.repliesTo {
                if repliesByParent[parentId] == nil {
                    repliesByParent[parentId] = []
                }
                repliesByParent[parentId]?.append(reply)
            }
        }
        
        // Sort each reply thread by date
        for (parentId, _) in repliesByParent {
            repliesByParent[parentId]?.sort { $0.createdAt < $1.createdAt }
        }
        
        // Start with root posts only
        filtered = rootPosts
        
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
        
        // Apply sorting to root posts
        switch sortOption {
        case .newestFirst:
            filtered.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            filtered.sort { $0.createdAt < $1.createdAt }
        case .mostReplies:
            filtered.sort {
                let count1 = repliesByParent[$0.id]?.count ?? 0
                let count2 = repliesByParent[$1.id]?.count ?? 0
                return count1 > count2
            }
        case .recentlyActive:
            filtered.sort {
                let replies1 = repliesByParent[$0.id] ?? []
                let replies2 = repliesByParent[$1.id] ?? []
                let latest1 = replies1.map { $0.createdAt }.max() ?? $0.createdAt
                let latest2 = replies2.map { $0.createdAt }.max() ?? $1.createdAt
                return latest1 > latest2
            }
        }
        
        // Now build the final list with threads
        var threadedDigests: [Digest] = []
        for rootPost in filtered {
            threadedDigests.append(rootPost)
            // Add replies right after their parent (you could show these indented in the UI)
            if let replies = repliesByParent[rootPost.id] {
                threadedDigests.append(contentsOf: replies)
            }
        }
        
        return threadedDigests
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
            var discoveredTagsSet = Set<String>()
            let digestsLock = NSLock()
            var allDigestsDict = [String: Digest]()
            
            // Get date range
            let dateRange: (start: Date?, end: Date?)
            if dateRangeOption == .custom {
                dateRange = (customStartDate, customEndDate)
            } else {
                dateRange = dateRangeOption.dateRange
            }
            
            // Get nodes to query
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
            
            // PARALLEL FETCH: Create tasks for all tag/node combinations
            await withTaskGroup(of: [Digest].self) { group in
                for node in nodesToQuery {
                    // Determine tags to fetch - NO FILTERING, get everything the pod advertises
                    let tagsToFetch: [String]
                    if !selectedTags.isEmpty {
                        // User has manually selected tags to filter by
                        tagsToFetch = Array(selectedTags)
                    } else if !pod.cachedTags.isEmpty {
                        // Get ALL pod tags, not filtered
                        tagsToFetch = pod.cachedTags
                    } else if !node.advertisedTags.isEmpty {
                        // Fall back to node's advertised tags
                        tagsToFetch = node.advertisedTags
                    } else {
                        continue
                    }
                    
                    print("[PodFeedView] Starting parallel fetch from \(node.name) for \(tagsToFetch.count) tags")
                    
                    // Create a task for each tag
                    for tag in tagsToFetch {
                        group.addTask {
                            await fetchDigestsForTag(
                                tag: tag,
                                from: node,
                                podClient: podClient,
                                podKey: pod.presharedKey,
                                podName: pod.name,
                                dateRange: dateRange
                            )
                        }
                    }
                }
                
                // Collect results from all parallel tasks
                for await digestBatch in group {
                    digestsLock.lock()
                    
                    // Add ALL digests to dictionary (no filtering!)
                    for digest in digestBatch {
                        // Collect all tags
                        discoveredTagsSet.formUnion(digest.tags)
                        
                        // Merge digest if it already exists
                        if var existing = allDigestsDict[digest.id] {
                            var podSet = existing.inPodsSet
                            podSet.formUnion(digest.inPodsSet)
                            existing.inPods = Array(podSet)
                            allDigestsDict[digest.id] = existing
                        } else {
                            allDigestsDict[digest.id] = digest
                        }
                    }
                    
                    digestsLock.unlock()
                }
            }
            
            // Update discovered tags
            if !discoveredTagsSet.isEmpty {
                AppConfigStore.updateDiscoveredTags(podId: pod.id, tags: Array(discoveredTagsSet))
            }
            
            // IMPORTANT: Sort the digests by creation date!
            let sortedDigests = Array(allDigestsDict.values).sorted { $0.createdAt > $1.createdAt }
            
            await MainActor.run {
                self.digests = sortedDigests // Use sorted array
                self.allDiscoveredTags = Array(discoveredTagsSet)
                self.isLoading = false
                
                // Check for new replies
                let config = AppConfigStore.load()
                if let endpoint = config.endpoints.first {
                    NotificationManager.shared.checkForNewReplies(
                        in: self.digests,
                        deviceName: endpoint.device,
                        nodeName: endpoint.nodeName
                    )
                }
            }
            
            print("[PodFeedView] Total unique digests loaded: \(digests.count) (newest: \(sortedDigests.first?.createdAt ?? Date()))")
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isLoading = false
            }
        }
    }
    
    // Helper function to fetch all pages for a single tag
    private func fetchDigestsForTag(
        tag: String,
        from node: PodNode,
        podClient: PodClient,
        podKey: String,
        podName: String,
        dateRange: (start: Date?, end: Date?)
    ) async -> [Digest] {
        var tagDigests: [Digest] = []
        var currentPage = 1
        var hasMorePages = true
        
        while hasMorePages {
            do {
                let response = try await podClient.fetchDigests(
                    from: node,
                    tags: [tag],
                    podKey: podKey,
                    page: currentPage,
                    perPage: 100,
                    startDate: dateRange.start,
                    endDate: dateRange.end
                )
                
                // Convert entries
                let digestsFromPage = response.feedentries.compactMap { entry -> Digest? in
                    // FIX DATE PARSING - API returns format like "2025-10-13T01:17:11.303952"
                    var createdDate = Date()
                    if let dateString = entry.createdAt {
                        // This format has microseconds but no timezone - it's UTC
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                        formatter.timeZone = TimeZone(abbreviation: "UTC")
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        
                        if let date = formatter.date(from: dateString) {
                            createdDate = date
                        } else {
                            // Try without microseconds
                            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                            if let date = formatter.date(from: dateString) {
                                createdDate = date
                            }
                        }
                    }
                    
                    let tagNames = entry.tags?.map { $0.name } ?? []
                    
                    // Parse replies
                    // Parse replies - ROBUST VERSION
                    var repliesTo: String? = nil
                    if let content = entry.content {
                        if content.contains("@reply:") {
                            // Old format: @reply:12345
                            if let range = content.range(of: "@reply:") {
                                let afterReply = content[range.upperBound...]
                                if let spaceIndex = afterReply.firstIndex(of: " ") {
                                    repliesTo = String(afterReply[..<spaceIndex])
                                } else {
                                    repliesTo = String(afterReply)
                                }
                            }
                        } else if content.contains("@") && content.contains(".xyzpulseinfra.com.") {
                            // New format: @anything.xyzpulseinfra.com.DIGESTID.devicename
                            // Find the .xyzpulseinfra.com. part and get what's after it
                            if let range = content.range(of: ".xyzpulseinfra.com.") {
                                let afterDomain = content[range.upperBound...]
                                // Get everything up to the next dot (the digest ID)
                                if let nextDot = afterDomain.firstIndex(of: ".") {
                                    let digestId = String(afterDomain[..<nextDot])
                                    repliesTo = digestId
                                    print("[Reply Parse] Found reply to digest: \(digestId)")
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
                        inPods: [podName],
                        isMyPost: false,
                        isReplyToMe: false,
                        repliesTo: repliesTo
                    )
                }
                
                tagDigests.append(contentsOf: digestsFromPage)
                
                hasMorePages = currentPage < response.pages
                currentPage += 1
                
                if digestsFromPage.count > 0 {
                    print("[PodFeedView] Tag '\(tag)': got \(digestsFromPage.count) digests, newest: \(digestsFromPage.first?.createdAt ?? Date())")
                }
            } catch {
                print("Failed to fetch tag '\(tag)' from \(node.name): \(error)")
                break
            }
        }
        
        return tagDigests
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
