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
import android.widget.ImageView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.pulseai.kashstash.R
import com.pulseai.kashstash.pods.models.Digest
import android.widget.LinearLayout
import coil.load
import coil.transform.RoundedCornersTransformation

class DigestAdapter(
    private val onReplyClick: (Digest) -> Unit,
    private val onThreadClick: (Digest) -> Unit,
    private val onShareClick: (Digest) -> Unit,
    private val onItemClick: (Digest) -> Unit = {}
) : ListAdapter<Digest, DigestAdapter.DigestViewHolder>(DigestDiffCallback()) {

    // Track reply counts for each digest
    private val replyCountMap = mutableMapOf<String, Int>()

    // Cache parsed link previews to avoid re-parsing on scroll
    private val linkPreviewCache = mutableMapOf<String, LinkPreviewData>()

    fun updateReplyCounts(counts: Map<String, Int>) {
        replyCountMap.clear()
        replyCountMap.putAll(counts)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): DigestViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_digest, parent, false)
        return DigestViewHolder(view, onReplyClick, onThreadClick, onShareClick, onItemClick, replyCountMap, linkPreviewCache)
    }

    override fun onBindViewHolder(holder: DigestViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    data class LinkPreviewData(
        val url: String,
        val title: String,
        val description: String,
        val domain: String,
        val backgroundColor: Int,
        val thumbnailUrl: String? = null,
        val linkType: LinkType
    )

    enum class LinkType {
        YOUTUBE, TWITTER, GITHUB, REDDIT, IMAGE, GENERIC
    }

    class DigestViewHolder(
        itemView: View,
        private val onReplyClick: (Digest) -> Unit,
        private val onThreadClick: (Digest) -> Unit,
        private val onShareClick: (Digest) -> Unit,
        private val onItemClick: (Digest) -> Unit,
        private val replyCountMap: Map<String, Int>,
        private val linkPreviewCache: MutableMap<String, LinkPreviewData>
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
        private val linkPreviewImage: ImageView? = itemView.findViewById(R.id.linkPreviewImage)
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
            detectAndShowLinkPreview(digest)

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

        private fun detectAndShowLinkPreview(digest: Digest) {
            val urlPattern = Regex("https?://[\\w\\-._~:/?#\\[\\]@!$&'()*+,;=%]+")
            val firstUrl = urlPattern.find(digest.content)?.value

            if (firstUrl != null && linkPreviewContainer != null) {
                linkPreviewContainer.visibility = View.VISIBLE

                // Check cache first
                val previewData = linkPreviewCache.getOrPut(digest.id) {
                    parseLinkPreview(firstUrl)
                }

                // Set text content
                linkPreviewTitle?.text = previewData.title
                linkPreviewDescription?.text = previewData.description
                linkPreviewUrl?.text = previewData.domain
                linkPreviewContainer.setBackgroundColor(previewData.backgroundColor)

                // Load image if available
                if (previewData.thumbnailUrl != null && linkPreviewImage != null) {
                    linkPreviewImage.visibility = View.VISIBLE
                    linkPreviewImage.load(previewData.thumbnailUrl) {
                        crossfade(true)
                        transformations(RoundedCornersTransformation(8f))
                        placeholder(R.drawable.ic_image_placeholder) // You'll need to add this
                        error(R.drawable.ic_image_error) // You'll need to add this
                    }
                } else {
                    linkPreviewImage?.visibility = View.GONE
                }

                // Set click listener to open the link
                linkPreviewContainer.setOnClickListener {
                    try {
                        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW)
                        intent.data = android.net.Uri.parse(previewData.url)
                        itemView.context.startActivity(intent)
                    } catch (e: Exception) {
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

        private fun parseLinkPreview(url: String): LinkPreviewData {
            return when {
                // YouTube
                url.contains("youtube.com/watch") || url.contains("youtu.be/") -> {
                    val videoId = extractYouTubeVideoId(url)
                    LinkPreviewData(
                        url = url,
                        title = "📺 YouTube Video",
                        description = "Tap to watch on YouTube",
                        domain = extractDomain(url),
                        backgroundColor = 0x1AFF0000,
                        thumbnailUrl = videoId?.let { "https://img.youtube.com/vi/$it/mqdefault.jpg" },
                        linkType = LinkType.YOUTUBE
                    )
                }

                // Twitter/X
                url.contains("twitter.com") || url.contains("x.com") -> {
                    LinkPreviewData(
                        url = url,
                        title = "𝕏 Post",
                        description = "View on X (formerly Twitter)",
                        domain = extractDomain(url),
                        backgroundColor = 0x1A1DA1F2,
                        thumbnailUrl = null,
                        linkType = LinkType.TWITTER
                    )
                }

                // GitHub
                url.contains("github.com") -> {
                    LinkPreviewData(
                        url = url,
                        title = "🐙 GitHub",
                        description = extractGithubInfo(url),
                        domain = extractDomain(url),
                        backgroundColor = 0x1A238636,
                        thumbnailUrl = null,
                        linkType = LinkType.GITHUB
                    )
                }

                // Reddit
                url.contains("reddit.com") -> {
                    LinkPreviewData(
                        url = url,
                        title = "🟠 Reddit",
                        description = "View on Reddit",
                        domain = extractDomain(url),
                        backgroundColor = 0x1AFF4500,
                        thumbnailUrl = null,
                        linkType = LinkType.REDDIT
                    )
                }

                // Image URLs
                isImageUrl(url) -> {
                    LinkPreviewData(
                        url = url,
                        title = "🖼️ Image",
                        description = "Tap to view image",
                        domain = extractDomain(url),
                        backgroundColor = 0x1A007AFF,
                        thumbnailUrl = url, // Load the actual image
                        linkType = LinkType.IMAGE
                    )
                }

                // Generic link
                else -> {
                    val domain = extractDomain(url)
                    LinkPreviewData(
                        url = url,
                        title = "🔗 $domain",
                        description = "Tap to open link",
                        domain = domain,
                        backgroundColor = 0x1A007AFF,
                        thumbnailUrl = null,
                        linkType = LinkType.GENERIC
                    )
                }
            }
        }

        private fun extractYouTubeVideoId(url: String): String? {
            return try {
                when {
                    url.contains("youtu.be/") -> {
                        url.substringAfter("youtu.be/").substringBefore("?")
                    }
                    url.contains("youtube.com/watch?v=") -> {
                        url.substringAfter("v=").substringBefore("&")
                    }
                    else -> null
                }
            } catch (e: Exception) {
                null
            }
        }

        private fun extractDomain(url: String): String {
            return try {
                val uri = android.net.Uri.parse(url)
                val host = uri.host?.removePrefix("www.") ?: return url
                // For very long URLs, show domain + path hint
                val path = uri.path
                if (path != null && path.length > 20) {
                    "$host/...${path.takeLast(15)}"
                } else if (path != null && path.isNotEmpty() && path != "/") {
                    "$host$path"
                } else {
                    host
                }
            } catch (e: Exception) {
                // Fallback: extract manually
                url.substringAfter("://")
                    .substringBefore("/")
                    .removePrefix("www.")
                    .take(50) + if (url.length > 50) "..." else ""
            }
        }

        private fun extractGithubInfo(url: String): String {
            return when {
                url.contains("/pull/") -> "Pull Request"
                url.contains("/issues/") -> "Issue"
                url.contains("/releases/") -> "Release"
                url.contains("/commit/") -> "Commit"
                url.contains("/tree/") -> "Repository Branch"
                url.contains("/blob/") -> "File"
                else -> "Repository"
            }
        }

        private fun isImageUrl(url: String): Boolean {
            val imageExtensions = listOf(".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".bmp", ".ico")
            val lowerUrl = url.lowercase()
            return imageExtensions.any { lowerUrl.contains(it) }
        }

        private fun formatContentWithMentions(content: String): SpannableString {
            val spannable = SpannableString(content)

            // Highlight @mentions (full pod mention pattern)
            val mentionPattern = Regex("@[a-zA-Z0-9._-]+(\\.probes-[^\\s]+)?")
            mentionPattern.findAll(content).forEach { match ->
                spannable.setSpan(
                    ForegroundColorSpan(0xFF007AFF.toInt()),
                    match.range.first,
                    match.range.last + 1,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }

            // Highlight URLs
            val urlPattern = Regex("https?://[\\w\\-._~:/?#\\[\\]@!$&'()*+,;=%]+")
            urlPattern.findAll(content).forEach { match ->
                spannable.setSpan(
                    ForegroundColorSpan(0xFF00D9FF.toInt()),
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