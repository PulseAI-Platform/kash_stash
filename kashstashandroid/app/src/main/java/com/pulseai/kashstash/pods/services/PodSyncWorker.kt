package com.pulseai.kashstash.pods.services

import android.content.Context
import android.util.Log
import androidx.work.*
import com.pulseai.kashstash.ConfigManager
import com.pulseai.kashstash.pods.storage.PodDatabase
import com.pulseai.kashstash.pods.storage.PodPreferences
import com.pulseai.kashstash.pods.storage.PodRepository
import kotlinx.coroutines.flow.first
import java.util.concurrent.TimeUnit
import java.util.Date

class PodSyncWorker(
    context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    private val database = PodDatabase.getDatabase(context)
    private val repository = PodRepository(database.podDao())
    private val prefs = PodPreferences(context)
    private val podClient = PodClient()
    private val notificationManager = NotificationManager(context)

    override suspend fun doWork(): Result {
        Log.d("PodSyncWorker", "=== Worker started at ${Date()} ===")

        return try {
            // Sync device names from EndpointConfigs first
            Log.d("PodSyncWorker", "Step 1: Syncing device names from endpoints")
            try {
                BackgroundSyncManager.syncDeviceNamesFromEndpoints(applicationContext)
            } catch (e: Exception) {
                Log.e("PodSyncWorker", "Failed to sync device names", e)
                prefs.lastSyncError = "Failed to sync device names: ${e.message}"
                return Result.failure()
            }

            // Get device names from preferences
            val deviceNames = prefs.deviceNames
            Log.d("PodSyncWorker", "Step 2: Got device names: ${deviceNames.joinToString()}")

            if (deviceNames.isEmpty()) {
                Log.w("PodSyncWorker", "No device names configured, skipping sync")
                prefs.lastSyncTime = System.currentTimeMillis()
                prefs.lastSyncError = "No device names configured"
                return Result.success()
            }

            // Get all active pods
            Log.d("PodSyncWorker", "Step 3: Fetching active pods")
            val activePods = try {
                repository.getActivePods().first()
            } catch (e: Exception) {
                Log.e("PodSyncWorker", "Failed to get active pods", e)
                prefs.lastSyncError = "Failed to get active pods: ${e.message}"
                return Result.failure()
            }

            Log.d("PodSyncWorker", "Found ${activePods.size} active pods")

            if (activePods.isEmpty()) {
                Log.w("PodSyncWorker", "No active pods, skipping sync")
                prefs.lastSyncTime = System.currentTimeMillis()
                prefs.lastSyncError = "No active pods"
                return Result.success()
            }

            // Create aggregator with all device names
            Log.d("PodSyncWorker", "Step 4: Creating aggregator")
            val aggregator = MultiPodAggregator(podClient, repository, deviceNames)

            // Fetch digests from all pods
            Log.d("PodSyncWorker", "Step 5: Fetching digests from all pods...")
            val digests = try {
                aggregator.fetchFromAllPods(activePods)
            } catch (e: Exception) {
                Log.e("PodSyncWorker", "Failed to fetch digests", e)
                prefs.lastSyncError = "Failed to fetch digests: ${e.message}"
                return Result.retry()
            }

            Log.d("PodSyncWorker", "Fetched ${digests.size} total digests")

            // Store digests in database
            Log.d("PodSyncWorker", "Step 6: Storing digests in database")
            try {
                repository.insertDigests(digests)
            } catch (e: Exception) {
                Log.e("PodSyncWorker", "Failed to insert digests", e)
                prefs.lastSyncError = "Failed to store digests: ${e.message}"
                return Result.failure()
            }

            Log.d("PodSyncWorker", "Stored digests in database")

            // Check for notifications for each pod
            Log.d("PodSyncWorker", "Step 7: Checking for notifications")
            activePods.forEach { pod ->
                val podDigests = digests.filter { it.inPods.contains(pod.name) }
                Log.d("PodSyncWorker", "Checking ${podDigests.size} digests for pod: ${pod.name}")
                try {
                    notificationManager.checkForNewContent(podDigests, pod, deviceNames)
                } catch (e: Exception) {
                    Log.e("PodSyncWorker", "Failed to check notifications for ${pod.name}", e)
                }
            }

            // Update sync time
            prefs.lastSyncTime = System.currentTimeMillis()
            prefs.lastSyncError = null
            Log.d("PodSyncWorker", "=== Sync completed successfully at ${Date()} ===")

            // Cleanup old records periodically
            try {
                notificationManager.cleanupOldRecords()
            } catch (e: Exception) {
                Log.e("PodSyncWorker", "Failed to cleanup records", e)
            }

            Result.success()
        } catch (e: Exception) {
            Log.e("PodSyncWorker", "=== Sync failed with unexpected error ===", e)
            prefs.lastSyncError = "Unexpected error: ${e.message}"
            e.printStackTrace()
            Result.retry()
        }
    }

    companion object {
        private const val WORK_NAME = "pod_sync_work"

        fun schedulePeriodicSync(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val syncRequest = PeriodicWorkRequestBuilder<PodSyncWorker>(
                15, TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    10, TimeUnit.SECONDS
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                syncRequest
            )

            Log.d("PodSyncWorker", "Scheduled periodic sync every 15 minutes")
        }

        fun scheduleImmediateSync(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val syncRequest = OneTimeWorkRequestBuilder<PodSyncWorker>()
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                "pod_sync_immediate",
                ExistingWorkPolicy.REPLACE,
                syncRequest
            )

            Log.d("PodSyncWorker", "Scheduled immediate sync")
        }

        fun cancelSync(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            Log.d("PodSyncWorker", "Cancelled periodic sync")
        }
    }
}