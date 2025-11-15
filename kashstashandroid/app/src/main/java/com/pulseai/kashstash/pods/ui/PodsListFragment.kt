package com.pulseai.kashstash.pods.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.pulseai.kashstash.R
import com.pulseai.kashstash.pods.models.PodConfig
import com.pulseai.kashstash.pods.storage.PodDatabase
import com.pulseai.kashstash.pods.storage.PodRepository
import com.pulseai.kashstash.pods.services.BackgroundSyncManager
import kotlinx.coroutines.launch
import android.content.Context
import com.pulseai.kashstash.pods.services.PodClient
class PodsListFragment : Fragment() {

    private lateinit var repository: PodRepository
    private lateinit var adapter: PodConfigAdapter
    private lateinit var recyclerView: RecyclerView
    private lateinit var podCountText: TextView
    private lateinit var emptyState: View

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_pods_list, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        // Initialize repository
        val database = PodDatabase.getDatabase(requireContext())
        repository = PodRepository(database.podDao())

        // Setup toolbar
        val toolbar = view.findViewById<MaterialToolbar>(R.id.toolbar)
        toolbar.setNavigationOnClickListener {
            requireActivity().onBackPressed()
        }

        // Setup RecyclerView
        recyclerView = view.findViewById(R.id.podsRecyclerView)
        podCountText = view.findViewById(R.id.podCountText)
        emptyState = view.findViewById(R.id.emptyState)

        adapter = PodConfigAdapter(
            onViewClick = { pod -> navigateToPodDetail(pod) },
            onSettingsClick = { pod -> showPodSettings(pod) }
        )

        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter

        // Hide FAB since QR import is handled in main screen
        //view.findViewById<FloatingActionButton>(R.id.addPodFab)?.visibility = View.GONE

        // Observe pods
        observePods()
    }

    private fun observePods() {
        viewLifecycleOwner.lifecycleScope.launch {
            repository.getAllPods().collect { pods ->
                adapter.submitList(pods)
                updateUI(pods)
            }
        }
    }

    private fun updateUI(pods: List<PodConfig>) {
        val activeCount = pods.count { it.isActive }
        podCountText.text = if (pods.isEmpty()) {
            "No pods configured"
        } else {
            "${pods.size} pod${if (pods.size != 1) "s" else ""} configured${if (activeCount > 0) " ($activeCount active)" else ""}"
        }

        emptyState.visibility = if (pods.isEmpty()) View.VISIBLE else View.GONE
        recyclerView.visibility = if (pods.isEmpty()) View.GONE else View.VISIBLE
    }

    private fun navigateToPodDetail(pod: PodConfig) {
        val fragment = PodDetailFragment.newInstance(pod.id)
        parentFragmentManager.beginTransaction()
            .replace(R.id.fragment_container, fragment)
            .addToBackStack(null)
            .commit()
    }

    // Replace the existing showPodSettings method with:
    // Add this to PodsListFragment.kt
    private fun showDebugInfo(pod: PodConfig) {
        val debugInfo = StringBuilder()

        viewLifecycleOwner.lifecycleScope.launch {
            debugInfo.append("=== POD CONFIG ===\n")
            debugInfo.append("Name: ${pod.name}\n")
            debugInfo.append("URL: ${pod.entranceNodeUrl}\n")
            debugInfo.append("Key (first 5): ${pod.presharedKey.take(5)}...\n")
            debugInfo.append("Tags: ${pod.cachedTags.joinToString(", ")}\n")
            debugInfo.append("Active: ${pod.isActive}\n\n")

            debugInfo.append("=== ATTEMPTING DISCOVERY ===\n")

            try {
                // Try discovery with inline debug
                val client = PodClient()
                val fullUrl = when {
                    pod.entranceNodeUrl.endsWith("/api/pods/") -> pod.entranceNodeUrl
                    pod.entranceNodeUrl.endsWith("/api/pods") -> "${pod.entranceNodeUrl}/"
                    pod.entranceNodeUrl.endsWith("/") -> "${pod.entranceNodeUrl}api/pods/"
                    else -> "${pod.entranceNodeUrl}/api/pods/"
                }

                debugInfo.append("Full URL: ${fullUrl}advertise\n")
                debugInfo.append("Request body: {\"tags\": ${pod.cachedTags}}\n\n")

                val nodes = client.discoverNodes(pod)

                debugInfo.append("=== DISCOVERY RESULT ===\n")
                debugInfo.append("Nodes found: ${nodes.size}\n")
                nodes.forEach { node ->
                    debugInfo.append("- ${node.name}: ${node.nodeUrl}\n")
                }

            } catch (e: Exception) {
                debugInfo.append("ERROR: ${e.message}\n")
                debugInfo.append("Type: ${e.javaClass.simpleName}\n")
                e.cause?.let {
                    debugInfo.append("Cause: ${it.message}\n")
                }
            }

            // Show in dialog
            AlertDialog.Builder(requireContext())
                .setTitle("Debug Info")
                .setMessage(debugInfo.toString())
                .setPositiveButton("Copy") { _, _ ->
                    val clipboard = requireContext().getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    val clip = android.content.ClipData.newPlainText("Debug", debugInfo.toString())
                    clipboard.setPrimaryClip(clip)
                    Toast.makeText(requireContext(), "Copied to clipboard", Toast.LENGTH_SHORT).show()
                }
                .setNegativeButton("Close", null)
                .show()
        }
    }

    // Add "Debug" option to your pod settings menu
    private fun showPodSettings(pod: PodConfig) {
        val options = arrayOf(
            if (pod.isActive) "Deactivate" else "Activate",
            "Refresh",
            "Notification Settings",
            "View Nodes",
            "Debug Info",  // ADD THIS
            "Delete"
        )

        AlertDialog.Builder(requireContext())
            .setTitle(pod.name)
            .setItems(options) { _, which ->
                when (which) {
                    0 -> togglePodActive(pod)
                    1 -> refreshPod(pod)
                    2 -> showNotificationSettings(pod)
                    3 -> showNodeInfo(pod)
                    4 -> showDebugInfo(pod)  // ADD THIS
                    5 -> confirmDeletePod(pod)
                }
            }
            .show()
    }

    // ADD these new methods:
    private fun showNotificationSettings(pod: PodConfig) {
        val items = arrayOf("Notify on new posts", "Notify on replies")
        val checkedItems = booleanArrayOf(
            pod.notifyNewDigests,
            pod.notifyReplies
        )

        AlertDialog.Builder(requireContext())
            .setTitle("${pod.name} Notifications")
            .setMultiChoiceItems(items, checkedItems) { _, which, isChecked ->
                checkedItems[which] = isChecked
            }
            .setPositiveButton("Save") { _, _ ->
                viewLifecycleOwner.lifecycleScope.launch {
                    repository.updateNotificationSettings(
                        podId = pod.id,
                        notifyNewDigests = checkedItems[0],
                        notifyReplies = checkedItems[1]
                    )
                    Toast.makeText(requireContext(), "Settings saved", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showNodeInfo(pod: PodConfig) {
        viewLifecycleOwner.lifecycleScope.launch {
            val nodes = repository.getNodesForPod(pod.id)
            val message = if (nodes.isEmpty()) {
                "No nodes discovered yet. Tap Refresh to discover nodes."
            } else {
                "Active nodes (${nodes.size}):\n" +
                        nodes.joinToString("\n") { "• ${it.name}" }
            }

            AlertDialog.Builder(requireContext())
                .setTitle("${pod.name} Nodes")
                .setMessage(message)
                .setPositiveButton("OK", null)
                .show()
        }
    }

    private fun showNotificationStatus() {
        viewLifecycleOwner.lifecycleScope.launch {
            val status = BackgroundSyncManager.isProperlyConfigured(requireContext())

            val message = buildString {
                appendLine("Status: ${if (status.isFullyConfigured) "✓ Active" else "⚠ Incomplete"}")
                appendLine()
                appendLine("Device Names:")
                if (status.deviceNames.isEmpty()) {
                    appendLine("  None configured - scan a Post Key QR code")
                } else {
                    status.deviceNames.forEach { name ->
                        appendLine("  • $name")
                    }
                }
                appendLine()
                appendLine("Notification Permission: ${if (status.hasNotificationPermission) "✓ Granted" else "✗ Not granted"}")
                appendLine()
                if (status.lastSyncTime > 0) {
                    val minutesAgo = (System.currentTimeMillis() - status.lastSyncTime) / 60000
                    appendLine("Last sync: $minutesAgo minutes ago")
                } else {
                    appendLine("Never synced")
                }
            }

            AlertDialog.Builder(requireContext())
                .setTitle("Background Notifications")
                .setMessage(message)
                .setPositiveButton("Test Sync Now") { _, _ ->
                    BackgroundSyncManager.triggerImmediateSync(requireContext())
                    Toast.makeText(requireContext(), "Sync triggered", Toast.LENGTH_SHORT).show()
                }
                .setNegativeButton("Close", null)
                .show()
        }
    }
    private fun togglePodActive(pod: PodConfig) {
        viewLifecycleOwner.lifecycleScope.launch {
            repository.togglePodActive(pod.id, !pod.isActive)
            Toast.makeText(
                requireContext(),
                if (!pod.isActive) "Pod activated" else "Pod deactivated",
                Toast.LENGTH_SHORT
            ).show()
        }
    }

    private fun refreshPod(pod: PodConfig) {
        // Navigate to detail view which will trigger refresh
        navigateToPodDetail(pod)
    }

    private fun confirmDeletePod(pod: PodConfig) {
        AlertDialog.Builder(requireContext())
            .setTitle("Delete Pod")
            .setMessage("Are you sure you want to delete ${pod.name}?")
            .setPositiveButton("Delete") { _, _ ->
                deletePod(pod)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun deletePod(pod: PodConfig) {
        viewLifecycleOwner.lifecycleScope.launch {
            repository.deletePod(pod)
            Toast.makeText(requireContext(), "Pod deleted", Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        fun newInstance() = PodsListFragment()
    }
}
