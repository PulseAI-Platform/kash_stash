package com.pulseai.kashstash.pods.services

import android.content.Context
import android.util.Log
import com.pulseai.kashstash.ConfigManager
import com.pulseai.kashstash.pods.storage.PodPreferences

object BackgroundSyncManager {

    fun syncDeviceNamesFromEndpoints(context: Context) {
        try {
            val config = ConfigManager.load(context)
            val deviceNames = config.endpoints.map { it.device }.filter { it.isNotBlank() }.toSet()

            val prefs = PodPreferences(context)
            prefs.deviceNames = deviceNames

            Log.d("BackgroundSyncManager", "Synced ${deviceNames.size} device names: ${deviceNames.joinToString()}")

            if (deviceNames.isNotEmpty()) {
                try {
                    PodSyncWorker.schedulePeriodicSync(context)
                } catch (e: IllegalStateException) {
                    Log.w("BackgroundSyncManager", "WorkManager not ready yet, will schedule later")
                }
            }
        } catch (e: Exception) {
            Log.e("BackgroundSyncManager", "Error syncing device names", e)
        }
    }

    fun setBackgroundSyncEnabled(context: Context, enabled: Boolean) {
        try {
            if (enabled) {
                // Always sync device names first
                syncDeviceNamesFromEndpoints(context)

                val prefs = PodPreferences(context)

                // Schedule the work regardless - the worker will handle checking if configured
                PodSyncWorker.schedulePeriodicSync(context)

                if (prefs.deviceNames.isNotEmpty()) {
                    Log.d("BackgroundSyncManager", "Background sync enabled with ${prefs.deviceNames.size} device names")
                } else {
                    Log.w("BackgroundSyncManager", "Background sync scheduled but no device names configured yet")
                }
            } else {
                PodSyncWorker.cancelSync(context)
                Log.d("BackgroundSyncManager", "Background sync disabled")
            }
        } catch (e: Exception) {
            Log.e("BackgroundSyncManager", "Error setting background sync", e)
        }
    }
    fun triggerImmediateSync(context: Context) {
        try {
            syncDeviceNamesFromEndpoints(context)
            PodSyncWorker.scheduleImmediateSync(context)
        } catch (e: Exception) {
            Log.e("BackgroundSyncManager", "Error triggering immediate sync", e)
        }
    }

    fun isProperlyConfigured(context: Context): ConfigurationStatus {
        return try {
            val prefs = PodPreferences(context)
            val notificationManager = NotificationManager(context)

            ConfigurationStatus(
                deviceNames = prefs.deviceNames.toList(),
                hasNotificationPermission = notificationManager.hasPermission(),
                lastSyncTime = prefs.lastSyncTime,
                lastSyncError = prefs.lastSyncError
            )
        } catch (e: Exception) {
            Log.e("BackgroundSyncManager", "Error checking configuration", e)
            ConfigurationStatus(
                deviceNames = emptyList(),
                hasNotificationPermission = false,
                lastSyncTime = 0,
                lastSyncError = e.message
            )
        }
    }

    data class ConfigurationStatus(
        val deviceNames: List<String>,
        val hasNotificationPermission: Boolean,
        val lastSyncTime: Long,
        val lastSyncError: String?
    ) {
        val isFullyConfigured: Boolean
            get() = deviceNames.isNotEmpty() && hasNotificationPermission

        val summary: String
            get() = when {
                !hasNotificationPermission -> "Notification permission not granted"
                deviceNames.isEmpty() -> "No post keys configured"
                else -> "Monitoring replies to: ${deviceNames.joinToString()}"
            }
    }
}