package com.pulseai.kashstash.pods.ui

import android.text.format.DateUtils
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.pulseai.kashstash.R
import com.pulseai.kashstash.pods.models.Digest
import android.widget.LinearLayout

class DigestAdapter(
    private val onReplyClick: (Digest) -> Unit,
    private val onThreadClick: (Digest) -> Unit,
    private val onShareClick: (Digest) -> Unit,
    private val onItemClick: (Digest) -> Unit = {}  // Add item click for expanding/link preview
) : ListAdapter<Digest, DigestAdapter.DigestViewHolder>(DigestDiffCallback()) {

    // Track reply counts for each digest
    private val replyCountMap = mutableMapOf<String, Int>()

    fun updateReplyCounts(counts: Map<String, Int>) {
        replyCountMap.clear()
        replyCountMap.putAll(counts)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): DigestViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_digest, parent, false)
        return DigestViewHolder(view, onReplyClick, onThreadClick, onShareClick, onItemClick, replyCountMap)
    }

    override fun onBindViewHolder(holder: DigestViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    class DigestViewHolder(
        itemView: View,
        private val onReplyClick: (Digest) -> Unit,
        private val onThreadClick: (Digest) -> Unit,
        private val onShareClick: (Digest) -> Unit,
        private val onItemClick: (Digest) -> Unit,
        private val replyCountMap: Map<String, Int>
    ) : RecyclerView.ViewHolder(itemView) {

        private val podBadge: TextView = itemView.findViewById(R.id.podBadge)
        private val youBadge: TextView = itemView.findViewById(R.id.youBadge)
        private val digestTitle: TextView = itemView.findViewById(R.id.digestTitle)
        private val digestContent: TextView = itemView.findViewById(R.id.digestContent)
        private val digestTags: TextView = itemView.findViewById(R.id.digestTags)
        private val replyButton: Button = itemView.findViewById(R.id.replyButton)
        private val threadButton: Button = itemView.findViewById(R.id.threadButton)
        private val shareButton: Button = itemView.findViewById(R.id.shareButton)
        private val timestamp: TextView = itemView.findViewById(R.id.timestamp)

        // Link preview views
        private val linkPreviewContainer: LinearLayout? = itemView.findViewById(R.id.linkPreviewContainer)
        private val linkPreviewTitle: TextView? = itemView.findViewById(R.id.linkPreviewTitle)
        private val linkPreviewDescription: TextView? = itemView.findViewById(R.id.linkPreviewDescription)
        private val linkPreviewUrl: TextView? = itemView.findViewById(R.id.linkPreviewUrl)

        fun bind(digest: Digest) {
            // Pod badge
            if (digest.inPods.isNotEmpty()) {
                podBadge.text = digest.inPods.first()
                podBadge.visibility = View.VISIBLE
            } else {
                podBadge.visibility = View.GONE
            }

            // "You" badge for own posts
            youBadge.visibility = if (digest.isMyPost) View.VISIBLE else View.GONE

            // Title
            if (digest.title.isNotEmpty()) {
                digestTitle.text = digest.title
                digestTitle.visibility = View.VISIBLE
            } else {
                digestTitle.visibility = View.GONE
            }

            // Content with reply highlighting
            digestContent.text = formatContentWithMentions(digest.content)

            // Detect and show link preview
            detectAndShowLinkPreview(digest.content)

            // Tags
            if (digest.tags.isNotEmpty()) {
                digestTags.text = digest.tags.joinToString(" ") { "#$it" }
                digestTags.visibility = View.VISIBLE
            } else {
                digestTags.visibility = View.GONE
            }

            // Timestamp
            timestamp.text = formatTimestamp(digest.createdAt.time)

            // Reply indicator
            when {
                digest.isReplyToMe -> {
                    replyButton.setTextColor(0xFFBB86FC.toInt())
                    replyButton.text = "↩️ Reply to you"
                }
                digest.isReply -> {
                    replyButton.setTextColor(0xFF999999.toInt())
                    replyButton.text = "↩️ Reply"
                }
                else -> {
                    replyButton.setTextColor(0xFF007AFF.toInt())
                    replyButton.text = "↩️ Reply"
                }
            }

            // Thread button - show if this has replies OR is a reply itself
            val replyCount = replyCountMap[digest.id] ?: 0
            when {
                replyCount > 0 -> {
                    threadButton.visibility = View.VISIBLE
                    threadButton.text = "💬 $replyCount ${if (replyCount == 1) "reply" else "replies"}"
                }
                digest.isReply -> {
                    threadButton.visibility = View.VISIBLE
                    threadButton.text = "💬 View Thread"
                }
                else -> {
                    threadButton.visibility = View.GONE
                }
            }

            // Click listeners
            itemView.setOnClickListener { onItemClick(digest) }
            replyButton.setOnClickListener { onReplyClick(digest) }
            threadButton.setOnClickListener { onThreadClick(digest) }
            shareButton.setOnClickListener { onShareClick(digest) }
        }

        private fun detectAndShowLinkPreview(content: String) {
            val urlPattern = Regex("https?://[\\w\\-._~:/?#\\[\\]@!$&'()*+,;=]+")
            val firstUrl = urlPattern.find(content)?.value

            if (firstUrl != null && linkPreviewContainer != null) {
                linkPreviewContainer.visibility = View.VISIBLE

                // Extract domain for display
                val domain = extractDomain(firstUrl)
                linkPreviewUrl?.text = domain

                // Detect special types and set appropriate preview
                when {
                    firstUrl.contains("youtube.com") || firstUrl.contains("youtu.be") -> {
                        linkPreviewTitle?.text = "📺 YouTube Video"
                        linkPreviewDescription?.text = "Tap to watch on YouTube"
                        linkPreviewContainer.setBackgroundColor(0x1AFF0000)
                    }
                    firstUrl.contains("twitter.com") || firstUrl.contains("x.com") -> {
                        linkPreviewTitle?.text = "𝕏 Post"
                        linkPreviewDescription?.text = "View on X (formerly Twitter)"
                        linkPreviewContainer.setBackgroundColor(0x1A1DA1F2)
                    }
                    firstUrl.contains("github.com") -> {
                        linkPreviewTitle?.text = "🐙 GitHub"
                        linkPreviewDescription?.text = extractGithubInfo(firstUrl)
                        linkPreviewContainer.setBackgroundColor(0x1A238636)
                    }
                    firstUrl.contains("reddit.com") -> {
                        linkPreviewTitle?.text = "🟠 Reddit"
                        linkPreviewDescription?.text = "View on Reddit"
                        linkPreviewContainer.setBackgroundColor(0x1AFF4500)
                    }
                    isImageUrl(firstUrl) -> {
                        linkPreviewTitle?.text = "🖼️ Image"
                        linkPreviewDescription?.text = "Tap to view image"
                        linkPreviewContainer.setBackgroundColor(0x1A007AFF)
                    }
                    else -> {
                        linkPreviewTitle?.text = "🔗 ${domain}"
                        linkPreviewDescription?.text = "Tap to open link"
                        linkPreviewContainer.setBackgroundColor(0x1A007AFF)
                    }
                }

                // Set click listener to open the link
                linkPreviewContainer.setOnClickListener {
                    try {
                        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW)
                        intent.data = android.net.Uri.parse(firstUrl)
                        itemView.context.startActivity(intent)
                    } catch (e: Exception) {
                        // Handle case where no browser is available
                        android.widget.Toast.makeText(
                            itemView.context,
                            "Cannot open link",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            } else {
                linkPreviewContainer?.visibility = View.GONE
            }
        }

        private fun extractDomain(url: String): String {
            return try {
                val uri = android.net.Uri.parse(url)
                uri.host?.removePrefix("www.") ?: url
            } catch (e: Exception) {
                url
            }
        }

        private fun extractGithubInfo(url: String): String {
            return when {
                url.contains("/pull/") -> "Pull Request"
                url.contains("/issues/") -> "Issue"
                url.contains("/releases/") -> "Release"
                url.contains("/commit/") -> "Commit"
                else -> "Repository"
            }
        }

        private fun isImageUrl(url: String): Boolean {
            val imageExtensions = listOf(".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".bmp")
            return imageExtensions.any { url.lowercase().contains(it) }
        }

        private fun formatContentWithMentions(content: String): SpannableString {
            val spannable = SpannableString(content)

            // Highlight @mentions
            val mentionPattern = Regex("@[a-zA-Z0-9._-]+")
            mentionPattern.findAll(content).forEach { match ->
                spannable.setSpan(
                    ForegroundColorSpan(0xFF007AFF.toInt()),
                    match.range.first,
                    match.range.last + 1,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }

            return spannable
        }

        private fun formatTimestamp(time: Long): String {
            val now = System.currentTimeMillis()
            return when {
                DateUtils.isToday(time) -> "Today at ${android.text.format.DateFormat.format("h:mm a", time)}"
                now - time < DateUtils.WEEK_IN_MILLIS -> DateUtils.getRelativeTimeSpanString(
                    time, now, DateUtils.DAY_IN_MILLIS
                ).toString()
                else -> android.text.format.DateFormat.format("MMM d, yyyy", time).toString()
            }
        }
    }

    private class DigestDiffCallback : DiffUtil.ItemCallback<Digest>() {
        override fun areItemsTheSame(oldItem: Digest, newItem: Digest): Boolean {
            return oldItem.id == newItem.id
        }

        override fun areContentsTheSame(oldItem: Digest, newItem: Digest): Boolean {
            return oldItem == newItem
        }
    }
}