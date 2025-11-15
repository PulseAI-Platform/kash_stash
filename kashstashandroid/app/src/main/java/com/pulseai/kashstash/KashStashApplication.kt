package com.pulseai.kashstash

import android.app.Application
import android.util.Log
import androidx.work.Configuration
import androidx.work.WorkManager
import com.pulseai.kashstash.pods.services.BackgroundSyncManager

class KashStashApplication : Application(), Configuration.Provider {

    override fun onCreate() {
        super.onCreate()

        // Initialize WorkManager first
        try {
            WorkManager.initialize(this, workManagerConfiguration)
            Log.d("KashStashApplication", "WorkManager initialized")
        } catch (e: IllegalStateException) {
            // Already initialized
            Log.d("KashStashApplication", "WorkManager already initialized")
        }

        // Sync device names from endpoints
        BackgroundSyncManager.syncDeviceNamesFromEndpoints(this)

        // ALWAYS try to enable sync - it will be a no-op if not configured
        // This ensures sync starts when endpoints/pods are added
        BackgroundSyncManager.setBackgroundSyncEnabled(this, true)

        val status = BackgroundSyncManager.isProperlyConfigured(this)
        if (status.isFullyConfigured) {
            Log.d("KashStashApplication", "Background sync active: ${status.summary}")
        } else {
            Log.d("KashStashApplication", "Background sync scheduled but incomplete: ${status.summary}")
        }
    }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setMinimumLoggingLevel(Log.INFO)
            .build()
}