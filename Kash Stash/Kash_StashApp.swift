//
//  Kash_StashApp.swift
//  Kash Stash
//
//  Created by Matt on 10/12/25.
//

import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct Kash_StashApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var hasRunInitialCheck = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Check background refresh status
                    let status = UIApplication.shared.backgroundRefreshStatus
                    switch status {
                    case .available:
                        print("✅ Background refresh is AVAILABLE")
                    case .denied:
                        print("❌ Background refresh is DENIED - user must enable in Settings")
                    case .restricted:
                        print("⚠️ Background refresh is RESTRICTED")
                    @unknown default:
                        print("❓ Unknown background refresh status")
                    }
                    
                    // Schedule first background refresh
                    BackgroundTaskHandler.scheduleAppRefresh()
                    
                    // Check for updates when app becomes active
                    if !hasRunInitialCheck {
                        hasRunInitialCheck = true
                        print("🚀 Running initial check on app launch...")
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            await BackgroundTaskHandler.checkAllPodsForUpdates()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    print("📱 App entered foreground - checking for updates NOW")
                    Task {
                        await BackgroundTaskHandler.checkAllPodsForUpdates()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    print("📱 App going to background")
                    BackgroundTaskHandler.scheduleAppRefresh()
                }
        }
    }
}

// App Delegate - REGISTER BACKGROUND TASKS HERE
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("📱 AppDelegate didFinishLaunchingWithOptions")
        
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            } else {
                print("❌ Notification permission denied: \(error?.localizedDescription ?? "unknown")")
            }
        }
        
        // REGISTER BACKGROUND TASK HERE
        let taskRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.pulseai.kashstash.refresh",
            using: nil
        ) { task in
            print("🎯🎯🎯 BACKGROUND TASK HANDLER CALLED!")
            print("Task type: \(type(of: task))")
            
            if let refreshTask = task as? BGAppRefreshTask {
                BackgroundTaskHandler.handleAppRefresh(task: refreshTask)
            } else {
                print("⚠️ Unknown task type: \(type(of: task))")
                task.setTaskCompleted(success: false)
            }
        }
        
        print("📝 Background task registration result: \(taskRegistered)")
        
        // Check pending tasks
        BGTaskScheduler.shared.getPendingTaskRequests { tasks in
            print("🔍 Pending tasks after registration: \(tasks.count)")
            for task in tasks {
                print("  - \(task.identifier)")
            }
        }
        
        return true
    }
    
    // Handle notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("📬 Notification received while app in foreground")
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        print("📱 Notification tapped: \(response.notification.request.identifier)")
        completionHandler()
    }
}

// Background Task Handler
class BackgroundTaskHandler {
    
    static func scheduleAppRefresh() {
        // Cancel existing
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.pulseai.kashstash.refresh")
        
        let request = BGAppRefreshTaskRequest(identifier: "com.pulseai.kashstash.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 600) // 1 minute for testing
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Scheduled background refresh for \(request.earliestBeginDate!)")
            
            BGTaskScheduler.shared.getPendingTaskRequests { tasks in
                print("📋 Pending tasks: \(tasks.count)")
                for task in tasks {
                    print("  - \(task.identifier) at \(task.earliestBeginDate?.description ?? "?")")
                }
            }
        } catch {
            print("❌ Failed to schedule: \(error)")
        }
    }
    
    static func handleAppRefresh(task: BGAppRefreshTask) {
        print("🔄🔄🔄 Background refresh EXECUTING at \(Date())")
        
        // Schedule next one immediately
        scheduleAppRefresh()
        
        // Set up expiration handler
        task.expirationHandler = {
            print("⏰ Task expired")
        }
        
        // Do the work
        Task {
            print("🔄 Starting async work...")
            await checkAllPodsForUpdates()
            
            print("✅ Marking task complete")
            task.setTaskCompleted(success: true)
        }
    }
    
    static func checkAllPodsForUpdates() async {
        print("🔍 Checking all pods for updates at \(Date())...")
        
        let config = AppConfigStore.load()
        let podClient = PodClient()
        
        let deviceName = config.endpoints.first?.device ?? ""
        print("📱 Device name: \(deviceName)")
        
        let podsWithNotifications = config.podConfigs.filter { $0.notifyNewDigests || $0.notifyReplies }
        print("📬 Pods with notifications: \(podsWithNotifications.count)")
        
        for pod in podsWithNotifications {
            print("  Checking pod: \(pod.name)")
            
            guard pod.isActive else { continue }
            guard !pod.discoveredNodes.isEmpty else { continue }
            
            var allDigestsDict: [String: Digest] = [:]
            let yesterday = Date().addingTimeInterval(-86400)
            let now = Date()
            
            for node in pod.discoveredNodes.prefix(1) {
                let tagsToFetch = pod.cachedTags.isEmpty ? ["memes"] : Array(pod.cachedTags.prefix(3))
                
                for tag in tagsToFetch {
                    var currentPage = 1
                    var hasMorePages = true
                    
                    // FETCH ALL PAGES
                    while hasMorePages {
                        do {
                            print("    Fetching '\(tag)' page \(currentPage)...")
                            
                            let response = try await podClient.fetchDigests(
                                from: node,
                                tags: [tag],
                                podKey: pod.presharedKey,
                                page: currentPage,
                                perPage: 100, // Get 100 at a time
                                startDate: yesterday,
                                endDate: now
                            )
                            
                            print("    Got \(response.feedentries.count) entries for '\(tag)' (page \(currentPage)/\(response.pages))")
                            
                            for entry in response.feedentries {
                                var createdDate = Date()
                                if let dateString = entry.createdAt {
                                    let formatter = DateFormatter()
                                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                                    formatter.locale = Locale(identifier: "en_US_POSIX")
                                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                                    createdDate = formatter.date(from: dateString) ?? Date()
                                }
                                
                                let digest = Digest(
                                    id: String(entry.id),
                                    title: entry.title ?? "",
                                    content: entry.content ?? "",
                                    tags: entry.tags?.map { $0.name } ?? [],
                                    sourceNode: node.name,
                                    createdAt: createdDate,
                                    inPods: [pod.name],
                                    isMyPost: false,
                                    isReplyToMe: false,
                                    repliesTo: nil
                                )
                                
                                allDigestsDict[digest.id] = digest
                            }
                            
                            // Check if more pages exist
                            hasMorePages = currentPage < response.pages
                            currentPage += 1
                            
                            // Safety limit - don't fetch more than 10 pages
                            if currentPage > 10 {
                                print("    Stopping at 10 pages for safety")
                                break
                            }
                            
                        } catch {
                            print("    Error fetching '\(tag)' page \(currentPage): \(error)")
                            hasMorePages = false // Stop on error
                        }
                    }
                }
            }
            
            let allDigests = Array(allDigestsDict.values).sorted { $0.createdAt > $1.createdAt }
            print("  Total digests fetched: \(allDigests.count)")
            
            if let newest = allDigests.first {
                print("  Newest digest ID: \(newest.id)")
            }
            
            if !allDigests.isEmpty {
                print("  Checking \(allDigests.count) digests for new content...")
                NotificationManager.shared.checkForNewContent(
                    in: allDigests,
                    for: pod,
                    deviceName: deviceName
                )
            }
        }
        
        print("🔍 Finished checking all pods")
    }
}
