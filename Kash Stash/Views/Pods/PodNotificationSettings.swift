//
//  PodNotificationSettings.swift
//  Kash Stash
//
//  Created by Matt on 11/12/25.
//

// Create a new file: Views/Pods/PodNotificationSettings.swift
import SwiftUI
import UserNotifications

struct PodNotificationSettings: View {
    @Binding var pod: PodConfig
    @State private var notificationsEnabled = false
    @State private var showingNotificationAlert = false
    
    var body: some View {
        Form {
            Section(header: Text("Push Notifications")) {
                Toggle("New Digests", isOn: $pod.notifyNewDigests)
                    .disabled(!notificationsEnabled)
                
                Toggle("New Replies", isOn: $pod.notifyReplies)
                    .disabled(!notificationsEnabled)
                
                if !notificationsEnabled {
                    Button("Enable Notifications") {
                        requestNotificationPermission()
                    }
                    .foregroundColor(.blue)
                }
            }
            
            Section(footer: Text("You'll receive notifications when new content is posted to this pod.")) {
                if notificationsEnabled {
                    Label("Notifications are enabled", systemImage: "bell.fill")
                        .foregroundColor(.green)
                }
            }
        }
        .navigationTitle("\(pod.name) Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkNotificationStatus()
        }
        .alert("Notifications Disabled", isPresented: $showingNotificationAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable notifications in Settings to receive alerts for this pod.")
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    notificationsEnabled = true
                } else {
                    showingNotificationAlert = true
                }
            }
        }
    }
}
