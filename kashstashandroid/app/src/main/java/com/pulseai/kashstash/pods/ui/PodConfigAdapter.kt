package com.pulseai.kashstash.pods.ui

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.pulseai.kashstash.R
import com.pulseai.kashstash.pods.models.PodConfig
import java.util.concurrent.TimeUnit
import java.util.Date

class PodConfigAdapter(
    private val onViewClick: (PodConfig) -> Unit,
    private val onSettingsClick: (PodConfig) -> Unit
) : ListAdapter<PodConfig, PodConfigAdapter.PodViewHolder>(PodDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PodViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_pod_config, parent, false)
        return PodViewHolder(view, onViewClick, onSettingsClick)
    }

    override fun onBindViewHolder(holder: PodViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    class PodViewHolder(
        itemView: View,
        private val onViewClick: (PodConfig) -> Unit,
        private val onSettingsClick: (PodConfig) -> Unit
    ) : RecyclerView.ViewHolder(itemView) {

        private val podName: TextView = itemView.findViewById(R.id.podName)
        private val activeStatus: TextView = itemView.findViewById(R.id.activeStatus)
        private val podUrl: TextView = itemView.findViewById(R.id.podUrl)
        private val podTags: TextView = itemView.findViewById(R.id.podTags)
        private val nodeCount: TextView = itemView.findViewById(R.id.nodeCount)
        private val lastUpdated: TextView = itemView.findViewById(R.id.lastUpdated)
        private val viewButton: Button = itemView.findViewById(R.id.viewButton)
        private val settingsButton: Button = itemView.findViewById(R.id.settingsButton)

        fun bind(pod: PodConfig) {
            podName.text = pod.name
            podUrl.text = pod.entranceNodeUrl

            // Active status
            if (pod.isActive) {
                activeStatus.text = "ACTIVE"
                activeStatus.setBackgroundColor(0xFF34C759.toInt())
            } else {
                activeStatus.text = "INACTIVE"
                activeStatus.setBackgroundColor(0xFF666666.toInt())
            }

            // Tags
            if (pod.cachedTags.isNotEmpty()) {
                podTags.text = pod.cachedTags.joinToString(" ") { "#$it" }
                podTags.visibility = View.VISIBLE
            } else {
                podTags.visibility = View.GONE
            }

            // Node count
            val nodeCountText = "${pod.discoveredNodes.size} node${if (pod.discoveredNodes.size != 1) "s" else ""}"
            nodeCount.text = nodeCountText

            // Last updated
            if (pod.lastRefresh != null) {
                val diff = System.currentTimeMillis() - pod.lastRefresh
                lastUpdated.text = "Updated ${formatTimeDiff(diff)}"
            } else {
                lastUpdated.text = "Never updated"
            }

            // Click listeners
            viewButton.setOnClickListener { onViewClick(pod) }
            settingsButton.setOnClickListener { onSettingsClick(pod) }
        }

        private fun formatTimeDiff(diff: Long): String {
            return when {
                diff < TimeUnit.MINUTES.toMillis(1) -> "just now"
                diff < TimeUnit.HOURS.toMillis(1) -> "${TimeUnit.MILLISECONDS.toMinutes(diff)}m ago"
                diff < TimeUnit.DAYS.toMillis(1) -> "${TimeUnit.MILLISECONDS.toHours(diff)}h ago"
                diff < TimeUnit.DAYS.toMillis(7) -> "${TimeUnit.MILLISECONDS.toDays(diff)}d ago"
                else -> "over a week ago"
            }
        }
    }

    private class PodDiffCallback : DiffUtil.ItemCallback<PodConfig>() {
        override fun areItemsTheSame(oldItem: PodConfig, newItem: PodConfig): Boolean {
            return oldItem.id == newItem.id
        }

        override fun areContentsTheSame(oldItem: PodConfig, newItem: PodConfig): Boolean {
            return oldItem == newItem
        }
    }
}