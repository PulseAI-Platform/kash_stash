package com.pulseai.kashstash.pods.services

import android.content.Context
import androidx.work.*
import com.pulseai.kashstash.pods.storage.PodDatabase
import com.pulseai.kashstash.pods.storage.PodPreferences
import com.pulseai.kashstash.pods.storage.PodRepository
import kotlinx.coroutines.flow.first
import java.util.concurrent.TimeUnit

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
        return try {
            // Get device name
            val deviceName = prefs.deviceName ?: return Result.success()

            // Get all active pods
            val activePods = repository.getActivePods().first()

            if (activePods.isEmpty()) {
                return Result.success()
            }

            // Create aggregator
            val aggregator = MultiPodAggregator(podClient, repository, deviceName)

            // Fetch digests from all pods
            val digests = aggregator.fetchFromAllPods(activePods)

            // Store digests in database
            repository.insertDigests(digests)

            // Check for notifications for each pod
            activePods.forEach { pod ->
                val podDigests = digests.filter { it.inPods.contains(pod.name) }
                notificationManager.checkForNewContent(podDigests, pod, deviceName)
            }

            // Update sync time
            prefs.lastSyncTime = System.currentTimeMillis()

            // Cleanup old records periodically
            notificationManager.cleanupOldRecords()

            Result.success()
        } catch (e: Exception) {
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
                15, TimeUnit.MINUTES // Minimum interval is 15 minutes
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
        }

        fun cancelSync(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}