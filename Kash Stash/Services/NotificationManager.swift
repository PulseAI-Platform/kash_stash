// Services/NotificationManager.swift

import Foundation
import UserNotifications
import SwiftUI
import Combine

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var hasPermission = false
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.hasPermission = granted
            }
        }
    }
    
    func checkPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.hasPermission = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func scheduleLocalNotification(title: String, body: String, identifier: String) {
        guard hasPermission else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func checkForNewReplies(in digests: [Digest], deviceName: String, nodeName: String) {
        for digest in digests {
            let (isReplyToMe, fromDevice) = parseReplyInfoForNotification(
                digest: digest,
                myDeviceName: deviceName,
                myNodeName: nodeName
            )
            
            if isReplyToMe && !digest.wasNotified {
                scheduleLocalNotification(
                    title: "New Reply",
                    body: "You have a new reply from \(fromDevice ?? "someone") in \(digest.inPods.first ?? "a pod")",
                    identifier: "reply-\(digest.id)"
                )
                
                // Mark as notified
                markAsNotified(digestId: digest.id, type: .reply)
            }
        }
    }
    
    func checkForNewContent(
        in digests: [Digest],
        for pod: PodConfig,
        deviceName: String
    ) {
        guard pod.notifyNewDigests || pod.notifyReplies else { return }
        
        let cleanDeviceName = deviceName.lowercased().replacingOccurrences(of: " ", with: "-")
        
        // Sort digests by creation date
        let sortedDigests = digests.sorted { $0.createdAt > $1.createdAt }
        
        // Check for new digests (non-replies)
        if pod.notifyNewDigests {
            let newDigests = sortedDigests.filter { digest in
                // Skip if it's a reply
                if digest.repliesTo != nil || digest.content.hasPrefix("@") || digest.tags.contains("reply") {
                    return false
                }
                
                // Skip if we've already notified about it
                if wasNotified(digestId: digest.id, type: .digest) {
                    return false
                }
                
                // Skip if it's our own post
                if digest.tags.contains("from-\(cleanDeviceName)") {
                    return false
                }
                
                // Skip if it's older than 24 hours (avoid spam on first load)
                if digest.createdAt.timeIntervalSinceNow < -86400 {
                    return false
                }
                
                return true
            }
            
            for digest in newDigests.prefix(5) { // Limit to 5 notifications
                sendNewDigestNotification(digest: digest, pod: pod)
                markAsNotified(digestId: digest.id, type: .digest)
            }
        }
        
        // Check for new replies in this pod
        if pod.notifyReplies {
            let newReplies = sortedDigests.filter { digest in
                // Must be a reply
                guard digest.repliesTo != nil || digest.content.hasPrefix("@") || digest.tags.contains("reply") else {
                    return false
                }
                
                // Skip if already notified
                if wasNotified(digestId: digest.id, type: .reply) {
                    return false
                }
                
                // Skip if it's our own reply
                if digest.tags.contains("from-\(cleanDeviceName)") {
                    return false
                }
                
                // Check if it's a reply to us specifically
                let isReplyToMe = digest.content.lowercased().contains(".\(cleanDeviceName)")
                
                // Skip if older than 24 hours
                if digest.createdAt.timeIntervalSinceNow < -86400 {
                    return false
                }
                
                return isReplyToMe
            }
            
            for reply in newReplies.prefix(5) {
                sendReplyNotification(digest: reply, pod: pod)
                markAsNotified(digestId: reply.id, type: .reply)
            }
        }
    }
    
    private func parseReplyInfoForNotification(digest: Digest, myDeviceName: String, myNodeName: String) -> (isReplyToMe: Bool, fromDevice: String?) {
        let cleanDeviceName = myDeviceName.lowercased().replacingOccurrences(of: " ", with: "-")
        
        // Check if it's a reply to me
        let isReplyToMe = digest.content.lowercased().contains(".\(cleanDeviceName)")
        
        // Extract sender device from tags
        var fromDevice: String? = nil
        for tag in digest.tags {
            if tag.hasPrefix("from-") {
                fromDevice = String(tag.dropFirst(5))
                break
            }
        }
        
        return (isReplyToMe, fromDevice)
    }
    
    private func sendNewDigestNotification(digest: Digest, pod: PodConfig) {
        let content = UNMutableNotificationContent()
        content.title = "New post in \(pod.name)"
        
        // Extract author from tags if available
        var author: String? = nil
        for tag in digest.tags {
            if tag.hasPrefix("from-") {
                author = String(tag.dropFirst(5))
                break
            }
        }
        
        let preview = digest.title.isEmpty ?
            String(digest.content.prefix(100)) :
            digest.title
        
        if let author = author {
            content.body = "\(author): \(preview)"
        } else {
            content.body = preview
        }
        
        content.sound = .default
        content.badge = NSNumber(value: getBadgeCount() + 1)
        content.categoryIdentifier = "DIGEST"
        content.userInfo = ["podId": pod.id.uuidString, "digestId": digest.id]
        
        let request = UNNotificationRequest(
            identifier: "digest-\(digest.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func sendReplyNotification(digest: Digest, pod: PodConfig) {
        let content = UNMutableNotificationContent()
        content.title = "New reply in \(pod.name)"
        
        // Extract who replied
        var replier: String? = nil
        for tag in digest.tags {
            if tag.hasPrefix("from-") {
                replier = String(tag.dropFirst(5))
                break
            }
        }
        
        // Clean the content (remove @mention prefix)
        var cleanContent = digest.content
        if let firstSpace = cleanContent.firstIndex(of: " ") {
            cleanContent = String(cleanContent[cleanContent.index(after: firstSpace)...])
        }
        
        if let replier = replier {
            content.body = "\(replier) replied: \(String(cleanContent.prefix(100)))"
        } else {
            content.body = String(cleanContent.prefix(100))
        }
        
        content.sound = .default
        content.badge = NSNumber(value: getBadgeCount() + 1)
        content.categoryIdentifier = "REPLY"
        content.userInfo = ["podId": pod.id.uuidString, "digestId": digest.id]
        
        let request = UNNotificationRequest(
            identifier: "reply-\(digest.id)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func markAsNotified(digestId: String, type: NotificationType) {
        let key = type == .digest ? "notifiedDigestIds" : "notifiedReplyIds"
        var notifiedIds = UserDefaults.standard.stringArray(forKey: key) ?? []
        
        if !notifiedIds.contains(digestId) {
            notifiedIds.append(digestId)
            
            // Keep only last 1000 IDs to prevent infinite growth
            if notifiedIds.count > 1000 {
                notifiedIds = Array(notifiedIds.suffix(1000))
            }
            
            UserDefaults.standard.set(notifiedIds, forKey: key)
        }
    }
    
    private func wasNotified(digestId: String, type: NotificationType) -> Bool {
        let key = type == .digest ? "notifiedDigestIds" : "notifiedReplyIds"
        let notifiedIds = UserDefaults.standard.stringArray(forKey: key) ?? []
        return notifiedIds.contains(digestId)
    }
    
    private func getBadgeCount() -> Int {
        return UIApplication.shared.applicationIconBadgeNumber
    }
    
    func clearBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
    
    // Clear old notification records periodically
    func cleanupOldNotificationRecords() {
        let keys = ["notifiedDigestIds", "notifiedReplyIds"]
        for key in keys {
            if let ids = UserDefaults.standard.stringArray(forKey: key), ids.count > 500 {
                // Keep only the most recent 500
                let recentIds = Array(ids.suffix(500))
                UserDefaults.standard.set(recentIds, forKey: key)
            }
        }
    }
    
    private enum NotificationType {
        case digest
        case reply
    }
}

// Extension to check if digest was already notified
extension Digest {
    var wasNotified: Bool {
        let notifiedIds = UserDefaults.standard.stringArray(forKey: "notifiedDigestIds") ?? []
        let replyIds = UserDefaults.standard.stringArray(forKey: "notifiedReplyIds") ?? []
        return notifiedIds.contains(id) || replyIds.contains(id)
    }
}
