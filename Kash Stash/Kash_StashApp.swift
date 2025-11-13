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
    
    init() {
        // Register background task without capturing self
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.pulseai.kashstash.refresh",
            using: nil
        ) { task in
            BackgroundTaskHandler.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        // Request notification permissions on first launch
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            } else {
                print("❌ Notification permission denied: \(error?.localizedDescription ?? "unknown")")
            }
        }
        
        // Clear badge when app launches
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Schedule first background refresh
                    BackgroundTaskHandler.scheduleAppRefresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    // Schedule refresh when app goes to background
                    BackgroundTaskHandler.scheduleAppRefresh()
                }
        }
    }
}

// Separate class to handle background tasks
class BackgroundTaskHandler {
    
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.pulseai.kashstash.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes minimum
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 Scheduled background refresh for 15 mins from now")
        } catch {
            print("❌ Could not schedule app refresh: \(error)")
        }
    }
    
    static func handleAppRefresh(task: BGAppRefreshTask) {
        print("🔄 Background refresh started")
        
        // Schedule the next refresh
        scheduleAppRefresh()
        
        // Create a task to check for updates
        let refreshTask = Task {
            await checkAllPodsForUpdates()
            task.setTaskCompleted(success: true)
            print("✅ Background refresh completed")
        }
        
        // Handle expiration
        task.expirationHandler = {
            refreshTask.cancel()
            print("⏰ Background task expired")
        }
    }
    
    static func checkAllPodsForUpdates() async {
        print("🔍 Checking all pods for updates...")
        
        let config = AppConfigStore.load()
        let podClient = PodClient()
        
        // Get device name for filtering
        let deviceName = config.endpoints.first?.device ?? ""
        
        for pod in config.podConfigs where (pod.notifyNewDigests || pod.notifyReplies) {
            print("  Checking pod: \(pod.name)")
            
            // Only check active pods with notifications enabled
            guard pod.isActive else { continue }
            
            do {
                // Fetch recent digests (last 24 hours only to avoid spam)
                let yesterday = Date().addingTimeInterval(-86400)
                
                for node in pod.discoveredNodes.prefix(1) { // Check first node only for efficiency
                    let response = try await podClient.fetchDigests(
                        from: node,
                        tags: pod.cachedTags.isEmpty ? ["*"] : pod.cachedTags,
                        podKey: pod.presharedKey,
                        page: 1,
                        perPage: 20, // Only recent posts
                        startDate: yesterday,
                        endDate: nil
                    )
                    
                    // Convert to digests and check for new content
                    let digests = response.feedentries.compactMap { entry -> Digest? in
                        // Parse the digest (simplified version)
                        var createdDate = Date()
                        if let dateString = entry.createdAt {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                            formatter.locale = Locale(identifier: "en_US_POSIX")
                            formatter.timeZone = TimeZone(secondsFromGMT: 0)
                            createdDate = formatter.date(from: dateString) ?? Date()
                        }
                        
                        return Digest(
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
                    }
                    
                    // Check for new content using NotificationManager
                    if !digests.isEmpty {
                        print("  Found \(digests.count) digests in \(pod.name)")
                        NotificationManager.shared.checkForNewContent(
                            in: digests,
                            for: pod,
                            deviceName: deviceName
                        )
                    }
                }
            } catch {
                print("  Error checking pod \(pod.name): \(error)")
            }
        }
    }
}

// App Delegate for handling notification actions
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    // Handle notifications when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        print("📱 Notification tapped: \(response.notification.request.identifier)")
        // Handle navigation to specific pod/digest if needed
        completionHandler()
    }
}
