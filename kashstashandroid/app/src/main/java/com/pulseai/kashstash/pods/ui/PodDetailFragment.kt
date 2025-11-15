package com.pulseai.kashstash.pods.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.pulseai.kashstash.R
import com.pulseai.kashstash.pods.models.Digest
import com.pulseai.kashstash.pods.models.PodConfig
import com.pulseai.kashstash.pods.services.MultiPodAggregator
import com.pulseai.kashstash.pods.services.PodClient
import com.pulseai.kashstash.pods.storage.PodDatabase
import com.pulseai.kashstash.pods.storage.PodPreferences
import com.pulseai.kashstash.pods.storage.PodRepository
import com.pulseai.kashstash.ConfigManager
import com.pulseai.kashstash.EndpointConfig
import kotlinx.coroutines.launch
import java.util.Date
import android.util.Log
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import android.widget.ScrollView
import android.widget.CheckBox
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import android.util.Base64
import org.json.JSONObject
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import kotlinx.coroutines.CoroutineScope
import org.json.JSONArray

class PodDetailFragment : Fragment() {
    private lateinit var podClient: PodClient
    private lateinit var repository: PodRepository
    private lateinit var prefs: PodPreferences
    private lateinit var aggregator: MultiPodAggregator
    private lateinit var adapter: DigestAdapter
    private lateinit var recyclerView: RecyclerView
    private lateinit var digestCountText: TextView
    private var podId: String? = null
    private var currentPod: PodConfig? = null
    private var allDigests: List<Digest> = emptyList()
    private var filteredDigests: List<Digest> = emptyList()

    // Filter state
    private var selectedTags: Set<String> = emptySet()
    private var sortNewestFirst = true
    private var dateRangeStart: Date? = null
    private var dateRangeEnd: Date? = null

    private var searchJob: Job? = null
    private var tagSearchJob: Job? = null

    // Reply pattern for filtering
    private val replyPattern = Regex("@[^.]+\\.probes-[^.]+\\.xyzpulseinfra\\.com\\.[^.]+\\.[^\\s]+")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        podId = arguments?.getString(ARG_POD_ID)

        // Check if specific tags were passed (from menu selection)
        arguments?.getStringArrayList(ARG_SELECTED_TAGS)?.let {
            selectedTags = it.toSet()
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_pod_detail, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        // Initialize
        val database = PodDatabase.getDatabase(requireContext())
        repository = PodRepository(database.podDao())
        prefs = PodPreferences(requireContext())
        podClient = PodClient()

        // Get device names from preferences (synced from EndpointConfigs)
        val deviceNames = prefs.deviceNames
        aggregator = MultiPodAggregator(podClient, repository, deviceNames)

        // Setup toolbar
        val toolbar = view.findViewById<MaterialToolbar>(R.id.toolbar)
        toolbar.setNavigationOnClickListener {
            requireActivity().onBackPressedDispatcher.onBackPressed()
        }

        // Setup RecyclerView with optimizations
        recyclerView = view.findViewById(R.id.digestsRecyclerView)
        digestCountText = view.findViewById(R.id.digestCountText)

        recyclerView.apply {
            setHasFixedSize(true)
            setItemViewCacheSize(20)
            recycledViewPool.setMaxRecycledViews(0, 25)
            isNestedScrollingEnabled = false
        }

        adapter = DigestAdapter(
            onReplyClick = { digest -> showReplyDialog(digest) },
            onThreadClick = { digest -> showThreadDialog(digest) },
            onShareClick = { digest -> shareDigest(digest) },
            onItemClick = { digest -> showDigestDetail(digest) }
        )

        recyclerView.layoutManager = LinearLayoutManager(requireContext())
        recyclerView.adapter = adapter

        // Setup filter buttons
        setupFilterButtons(view)

        // Setup search with debouncing
        val searchInput = view.findViewById<EditText>(R.id.searchInput)
        searchInput.addTextChangedListener(object : android.text.TextWatcher {
            override fun afterTextChanged(s: android.text.Editable?) {
                searchJob?.cancel()
                searchJob = viewLifecycleOwner.lifecycleScope.launch {
                    delay(300)
                    filterDigests(s?.toString())
                }
            }
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
        })

        // REMOVE/HIDE FAB - No posting allowed, only sharing
        view.findViewById<FloatingActionButton>(R.id.newPostFab).visibility = View.GONE

        // Load pod and digests
        loadPodAndDigests()
    }
    private fun setupFilterButtons(view: View) {
        // Date range button
        view.findViewById<LinearLayout>(R.id.dateRangeButton).setOnClickListener {
            showDateRangeDialog()
        }

        // Sort button
        view.findViewById<LinearLayout>(R.id.sortButton).setOnClickListener { sortButton ->
            sortNewestFirst = !sortNewestFirst
            val sortText = if (sortNewestFirst) "⬇️  Sort: Newest First" else "⬆️  Sort: Oldest First"
            (sortButton as LinearLayout).let { layout ->
                for (i in 0 until layout.childCount) {
                    val child = layout.getChildAt(i)
                    if (child is TextView) {
                        child.text = sortText
                        break
                    }
                }
            }
            filterDigests()
        }

        // Tag filter button
        view.findViewById<LinearLayout>(R.id.tagFilterButton).setOnClickListener {
            showTagFilterDialog()
        }
    }

    private fun showDateRangeDialog() {
        val options = arrayOf("Last 24 Hours", "Last 7 Days", "Last 30 Days", "All Time")
        AlertDialog.Builder(requireContext())
            .setTitle("Select Date Range")
            .setItems(options) { _, which ->
                val now = Date()
                when (which) {
                    0 -> {
                        dateRangeStart = Date(now.time - 24 * 60 * 60 * 1000L)
                        dateRangeEnd = now
                    }
                    1 -> {
                        dateRangeStart = Date(now.time - 7 * 24 * 60 * 60 * 1000L)
                        dateRangeEnd = now
                    }
                    2 -> {
                        dateRangeStart = Date(now.time - 30 * 24 * 60 * 60 * 1000L)
                        dateRangeEnd = now
                    }
                    3 -> {
                        dateRangeStart = null
                        dateRangeEnd = null
                    }
                }
                filterDigests()
            }
            .show()
    }

    private fun showTagFilterDialog() {
        viewLifecycleOwner.lifecycleScope.launch {
            val allTags = withContext(Dispatchers.IO) {
                allDigests.flatMap { it.tags }.distinct().sorted()
            }

            if (allTags.isEmpty()) {
                Toast.makeText(requireContext(), "No tags available", Toast.LENGTH_SHORT).show()
                return@launch
            }

            withContext(Dispatchers.Main) {
                val dialogView = LinearLayout(requireContext()).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(16, 16, 16, 16)
                }

                val searchInput = EditText(requireContext()).apply {
                    hint = "Search tags..."
                    setSingleLine(true)
                }
                dialogView.addView(searchInput)

                val scrollView = ScrollView(requireContext()).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        0,
                        1f
                    )
                }

                val checkBoxContainer = LinearLayout(requireContext()).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(0, 16, 0, 0)
                }
                scrollView.addView(checkBoxContainer)
                dialogView.addView(scrollView)

                val originalSelectedTags = selectedTags.toSet()

                fun updateTagList(filter: String = "") {
                    tagSearchJob?.cancel()
                    tagSearchJob = viewLifecycleOwner.lifecycleScope.launch {
                        val filteredTags = withContext(Dispatchers.IO) {
                            if (filter.isBlank()) {
                                allTags.take(50)
                            } else {
                                allTags.filter { it.contains(filter, ignoreCase = true) }.take(50)
                            }
                        }

                        withContext(Dispatchers.Main) {
                            checkBoxContainer.removeAllViews()

                            val totalCount = if (filter.isBlank()) allTags.size else {
                                allTags.count { it.contains(filter, ignoreCase = true) }
                            }

                            val countText = TextView(requireContext()).apply {
                                text = when {
                                    totalCount > 50 -> "Showing 50 of $totalCount tags"
                                    else -> "$totalCount tags"
                                }
                                textSize = 12f
                                setTextColor(0xFF666666.toInt())
                                setPadding(0, 0, 0, 8)
                            }
                            checkBoxContainer.addView(countText)

                            filteredTags.forEach { tag ->
                                val checkBox = CheckBox(requireContext()).apply {
                                    text = "#$tag"
                                    isChecked = selectedTags.contains(tag)
                                    setOnCheckedChangeListener { _, isChecked ->
                                        selectedTags = if (isChecked) {
                                            selectedTags + tag
                                        } else {
                                            selectedTags - tag
                                        }
                                    }
                                }
                                checkBoxContainer.addView(checkBox)
                            }

                            if (totalCount > 50) {
                                val hintText = TextView(requireContext()).apply {
                                    text = "Use search to find more tags"
                                    textSize = 11f
                                    setTextColor(0xFF999999.toInt())
                                    setPadding(0, 16, 0, 0)
                                }
                                checkBoxContainer.addView(hintText)
                            }
                        }
                    }
                }

                updateTagList()

                searchInput.addTextChangedListener(object : android.text.TextWatcher {
                    override fun afterTextChanged(s: android.text.Editable?) {
                        tagSearchJob?.cancel()
                        tagSearchJob = viewLifecycleOwner.lifecycleScope.launch {
                            delay(300)
                            updateTagList(s?.toString() ?: "")
                        }
                    }
                    override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                    override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                })

                AlertDialog.Builder(requireContext())
                    .setTitle("Filter by Tags")
                    .setView(dialogView)
                    .setPositiveButton("Apply") { _, _ ->
                        filterDigests()
                    }
                    .setNeutralButton("Clear All") { _, _ ->
                        selectedTags = emptySet()
                        filterDigests()
                    }
                    .setNegativeButton("Cancel") { _, _ ->
                        selectedTags = originalSelectedTags
                    }
                    .show()
            }
        }
    }

    private fun calculateReplyCounts(digests: List<Digest>): Map<String, Int> {
        val counts = mutableMapOf<String, Int>()

        digests.forEach { digest ->
            // CORRECT PATTERN: @podname.probes-nodename.xyzpulseinfra.com.digestid.devicename
            val replyPattern = Regex("@[^.]+\\.probes-[^.]+\\.xyzpulseinfra\\.com\\.([^.]+)\\.[^\\s]+")
            replyPattern.findAll(digest.content).forEach { match ->
                val digestId = match.groupValues.getOrNull(1)
                if (digestId != null) {
                    counts[digestId] = (counts[digestId] ?: 0) + 1
                    Log.d("PodDetailFragment", "Found reply to digest: $digestId")
                }
            }
        }

        Log.d("PodDetailFragment", "Reply counts: $counts")
        return counts
    }

    private fun filterDigests(searchQuery: String? = null) {
        searchJob?.cancel()

        searchJob = viewLifecycleOwner.lifecycleScope.launch {
            val filtered = withContext(Dispatchers.Default) {
                val result = mutableListOf<Digest>()

                for (digest in allDigests) {
                    var passesFilter = true

                    // FILTER OUT REPLIES - Don't show any digest that contains reply syntax
                    if (replyPattern.containsMatchIn(digest.content)) {
                        passesFilter = false
                        Log.d("PodDetailFragment", "Filtering out reply digest: ${digest.id}")
                    }

                    if (passesFilter) {
                        dateRangeStart?.let {
                            if (digest.createdAt.before(it)) passesFilter = false
                        }
                        dateRangeEnd?.let {
                            if (digest.createdAt.after(it)) passesFilter = false
                        }
                    }

                    if (passesFilter && selectedTags.isNotEmpty()) {
                        passesFilter = digest.tags.any { selectedTags.contains(it) }
                    }

                    if (passesFilter && !searchQuery.isNullOrBlank()) {
                        val query = searchQuery.lowercase()
                        passesFilter = digest.tags.any { it.lowercase().contains(query) } ||
                                digest.title.lowercase().contains(query) ||
                                digest.content.take(200).lowercase().contains(query)
                    }

                    if (passesFilter) {
                        result.add(digest)
                    }
                }

                if (sortNewestFirst) {
                    result.sortByDescending { it.createdAt }
                } else {
                    result.sortBy { it.createdAt }
                }

                result
            }

            withContext(Dispatchers.Main) {
                filteredDigests = filtered

                val counts = withContext(Dispatchers.Default) {
                    calculateReplyCounts(allDigests)
                }
                adapter.updateReplyCounts(counts)

                adapter.submitList(filtered)

                val totalCount = allDigests.size
                val repliesFiltered = totalCount - filtered.size
                digestCountText.text = "${filtered.size} DIGESTS (${repliesFiltered} replies hidden)"
            }
        }
    }

    private fun loadPodAndDigests() {
        viewLifecycleOwner.lifecycleScope.launch {
            podId?.let { id ->
                currentPod = repository.getPodById(id)
                currentPod?.let { pod ->
                    view?.findViewById<MaterialToolbar>(R.id.toolbar)?.title = pod.name
                    fetchDigests(pod)
                }
            }
        }
    }

    private fun fetchDigests(pod: PodConfig) {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                digestCountText.text = "Loading..."

                if (pod.discoveredNodes.isEmpty()) {
                    Log.d("PodDetailFragment", "No nodes cached, discovering...")
                    val nodes = podClient.discoverNodes(pod)
                    if (nodes.isNotEmpty()) {
                        Log.d("PodDetailFragment", "Discovered ${nodes.size} nodes")
                        val updatedPod = pod.copy(discoveredNodes = nodes)
                        repository.updatePod(updatedPod)
                        repository.updateNodesForPod(pod.id, nodes)
                        currentPod = updatedPod
                    }
                }

                val digests = aggregator.refreshPod(currentPod ?: pod)
                Log.d("PodDetailFragment", "Got ${digests.size} digests")

                repository.insertDigests(digests)
                allDigests = digests

                val replyCounts = calculateReplyCounts(allDigests)
                adapter.updateReplyCounts(replyCounts)

                if (selectedTags.isNotEmpty()) {
                    filterDigests()
                } else {
                    // Filter out replies even on initial load
                    val nonReplyDigests = digests.filter { !replyPattern.containsMatchIn(it.content) }
                    filteredDigests = nonReplyDigests.sortedByDescending { it.createdAt }
                    adapter.submitList(filteredDigests)

                    val repliesCount = digests.size - nonReplyDigests.size
                    digestCountText.text = "${filteredDigests.size} DIGESTS (${repliesCount} replies hidden)"
                }

            } catch (e: Exception) {
                Log.e("PodDetailFragment", "Failed to fetch digests", e)
                Toast.makeText(
                    requireContext(),
                    "Failed to fetch digests: ${e.message}",
                    Toast.LENGTH_LONG
                ).show()
                loadCachedDigests()
            }
        }
    }

    private fun loadCachedDigests() {
        viewLifecycleOwner.lifecycleScope.launch {
            repository.getRecentDigests().collect { cachedDigests ->
                allDigests = cachedDigests
                val replyCounts = calculateReplyCounts(allDigests)
                adapter.updateReplyCounts(replyCounts)

                // Filter out replies from cached digests too
                val nonReplyDigests = cachedDigests.filter { !replyPattern.containsMatchIn(it.content) }
                filteredDigests = nonReplyDigests.sortedByDescending { it.createdAt }
                adapter.submitList(filteredDigests)

                val repliesCount = cachedDigests.size - nonReplyDigests.size
                digestCountText.text = "${filteredDigests.size} DIGESTS (cached, ${repliesCount} replies hidden)"
            }
        }
    }

    private fun showDigestDetail(digest: Digest) {
        val dialogView = ScrollView(requireContext()).apply {
            setPadding(24, 24, 24, 24)
        }

        val contentLayout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }

        // Title (if exists)
        if (digest.title.isNotEmpty()) {
            contentLayout.addView(TextView(requireContext()).apply {
                text = digest.title
                textSize = 20f
                setTextColor(0xFFFFFFFF.toInt())
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setPadding(0, 0, 0, 16)
                setTextIsSelectable(true)
            })
        }

        // Author info
        val fromTag = digest.tags.firstOrNull { it.startsWith("from-") }
        if (fromTag != null) {
            contentLayout.addView(TextView(requireContext()).apply {
                text = "From: ${fromTag.removePrefix("from-")}"
                textSize = 14f
                setTextColor(0xFF007AFF.toInt())
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setPadding(0, 0, 0, 12)
                setTextIsSelectable(true)
            })
        }

        // Main content - selectable and linkified
        contentLayout.addView(TextView(requireContext()).apply {
            text = digest.content
            textSize = 16f
            setTextColor(0xFFEEEEEE.toInt())
            setPadding(0, 0, 0, 16)
            setTextIsSelectable(true)

            // Enable link detection
            autoLinkMask = android.text.util.Linkify.WEB_URLS
            linksClickable = true

            // Linkify the text
            android.text.util.Linkify.addLinks(this, android.text.util.Linkify.WEB_URLS)

            // Make links clickable
            movementMethod = android.text.method.LinkMovementMethod.getInstance()

            // Highlight @mentions and #tags
            val spannable = android.text.SpannableString(digest.content)

            // Highlight @mentions
            val mentionPattern = Regex("@[a-zA-Z0-9._-]+(\\.probes-[^\\s]+)?")
            mentionPattern.findAll(digest.content).forEach { match ->
                spannable.setSpan(
                    android.text.style.ForegroundColorSpan(0xFF007AFF.toInt()),
                    match.range.first,
                    match.range.last + 1,
                    android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }

            // Highlight #tags
            val tagPattern = Regex("#[a-zA-Z0-9_-]+")
            tagPattern.findAll(digest.content).forEach { match ->
                spannable.setSpan(
                    android.text.style.ForegroundColorSpan(0xFF00D9FF.toInt()),
                    match.range.first,
                    match.range.last + 1,
                    android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }

            setText(spannable, TextView.BufferType.SPANNABLE)
        })

        // Separator line
        contentLayout.addView(View(requireContext()).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                2
            )
            setBackgroundColor(0xFF333333.toInt())
            val margin = LinearLayout.LayoutParams(layoutParams as LinearLayout.LayoutParams).apply {
                setMargins(0, 0, 0, 16)
            }
            layoutParams = margin
        })

        // Tags section
        if (digest.tags.isNotEmpty()) {
            contentLayout.addView(TextView(requireContext()).apply {
                text = "Tags:"
                textSize = 12f
                setTextColor(0xFF999999.toInt())
                setPadding(0, 0, 0, 8)
            })

            contentLayout.addView(TextView(requireContext()).apply {
                text = digest.tags.joinToString(" ") { "#$it" }
                textSize = 14f
                setTextColor(0xFF007AFF.toInt())
                setPadding(0, 0, 0, 16)
                setTextIsSelectable(true)
            })
        }

        // Timestamp
        contentLayout.addView(TextView(requireContext()).apply {
            text = "Posted: ${android.text.format.DateFormat.format("MMM d, yyyy 'at' h:mm a", digest.createdAt)}"
            textSize = 12f
            setTextColor(0xFF666666.toInt())
            setPadding(0, 0, 0, 8)
        })

        // Digest ID (for debugging/reference)
        contentLayout.addView(TextView(requireContext()).apply {
            text = "ID: ${digest.id}"
            textSize = 10f
            setTextColor(0xFF444444.toInt())
            setTextIsSelectable(true)
        })

        dialogView.addView(contentLayout)

        AlertDialog.Builder(requireContext())
            .setTitle("Full Post")
            .setView(dialogView)
            .setPositiveButton("Reply") { _, _ ->
                showReplyDialog(digest)
            }
            .setNeutralButton("Share") { _, _ ->
                shareDigest(digest)
            }
            .setNegativeButton("Close", null)
            .show()
    }

    private fun showReplyDialog(digest: Digest, fromThread: Boolean = false) {
        val config = ConfigManager.load(requireContext())
        val endpoint = config.endpoints.getOrNull(config.lastUsedEndpoint)

        if (endpoint == null) {
            Toast.makeText(requireContext(), "No endpoint configured! Configure in main app.", Toast.LENGTH_LONG).show()
            return
        }

        val dialogView = ScrollView(requireContext()).apply {
            setPadding(16, 16, 16, 16)
        }

        val contentLayout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }

        // Original card
        val originalCard = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFF1A1A1D.toInt())
            setPadding(16, 16, 16, 16)
        }

        originalCard.addView(TextView(requireContext()).apply {
            text = "Replying to:"
            textSize = 12f
            setTextColor(0xFF666666.toInt())
        })

        originalCard.addView(TextView(requireContext()).apply {
            text = digest.title.ifEmpty { "Untitled" }
            textSize = 16f
            setTextColor(0xFFFFFFFF.toInt())
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(0, 8, 0, 4)
        })

        originalCard.addView(TextView(requireContext()).apply {
            text = if (digest.content.length > 200) {
                digest.content.substring(0, 200) + "..."
            } else {
                digest.content
            }
            textSize = 14f
            setTextColor(0xFFCCCCCC.toInt())
            setPadding(0, 4, 0, 0)
        })

        contentLayout.addView(originalCard)
        contentLayout.addView(View(requireContext()).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 24)
        })

        // Reply input
        contentLayout.addView(TextView(requireContext()).apply {
            text = "Your reply (as ${endpoint.device}):"
            textSize = 14f
            setTextColor(0xFF007AFF.toInt())
            setPadding(0, 0, 0, 8)
        })

        val replyInput = EditText(requireContext()).apply {
            hint = "What are your thoughts?"
            minLines = 4
            maxLines = 8
            gravity = android.view.Gravity.TOP
            setBackgroundColor(0xFF222227.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            setHintTextColor(0xFF666666.toInt())
            setPadding(16, 16, 16, 16)
            inputType = android.text.InputType.TYPE_CLASS_TEXT or
                    android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                    android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
        }
        contentLayout.addView(replyInput)

        // Character counter
        val charCounter = TextView(requireContext()).apply {
            text = "0 / 500"
            textSize = 12f
            setTextColor(0xFF666666.toInt())
            gravity = android.view.Gravity.END
            setPadding(0, 8, 0, 0)
        }
        contentLayout.addView(charCounter)

        replyInput.addTextChangedListener(object : android.text.TextWatcher {
            override fun afterTextChanged(s: android.text.Editable?) {
                val length = s?.length ?: 0
                charCounter.text = "$length / 500"
                charCounter.setTextColor(if (length > 500) 0xFFFF0000.toInt() else 0xFF666666.toInt())
            }
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
        })

        // TAG SELECTION SECTION
        contentLayout.addView(TextView(requireContext()).apply {
            text = "Include tags from original post:"
            textSize = 14f
            setTextColor(0xFF007AFF.toInt())
            setPadding(0, 16, 0, 8)
        })

        val tagContainer = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }

        val selectedReplyTags = mutableSetOf<String>()

        // Add checkboxes for original tags (excluding from- tags)
        digest.tags.filter { !it.startsWith("from-") }.forEach { tag ->
            val checkBox = CheckBox(requireContext()).apply {
                text = "#$tag"
                isChecked = true // Auto-select all non-from tags
                setTextColor(0xFFFFFFFF.toInt())
                setOnCheckedChangeListener { _, isChecked ->
                    if (isChecked) {
                        selectedReplyTags.add(tag)
                    } else {
                        selectedReplyTags.remove(tag)
                    }
                }
            }
            selectedReplyTags.add(tag) // Add to selected since we're auto-checking
            tagContainer.addView(checkBox)
        }

        if (tagContainer.childCount > 0) {
            contentLayout.addView(tagContainer)
        }

        // Additional tags input
        contentLayout.addView(TextView(requireContext()).apply {
            text = "Add new tags (optional):"
            textSize = 14f
            setTextColor(0xFF007AFF.toInt())
            setPadding(0, 12, 0, 8)
        })

        val additionalTagsInput = EditText(requireContext()).apply {
            hint = "space separated tags"
            setSingleLine(true)
            setBackgroundColor(0xFF222227.toInt())
            setTextColor(0xFFFFFFFF.toInt())
            setHintTextColor(0xFF666666.toInt())
            setPadding(16, 16, 16, 16)
        }
        contentLayout.addView(additionalTagsInput)

        contentLayout.addView(TextView(requireContext()).apply {
            text = "💡 Your reply will automatically mention the original poster"
            textSize = 11f
            setTextColor(0xFF007AFF.toInt())
            setPadding(0, 12, 0, 0)
        })

        dialogView.addView(contentLayout)

        AlertDialog.Builder(requireContext())
            .setTitle("Reply to Post")
            .setView(dialogView)
            .setPositiveButton("Send Reply") { _, _ ->
                val replyText = replyInput.text.toString().trim()
                if (replyText.isNotBlank() && replyText.length <= 500) {
                    val newTags = additionalTagsInput.text.toString()
                        .split(" ")
                        .map { it.trim().removePrefix("#") }
                        .filter { it.isNotBlank() }

                    val allTags = (selectedReplyTags + newTags).toList()
                    sendReplyViaEndpoint(digest, replyText, endpoint, allTags, fromThread)
                }
            }
            .setNegativeButton("Cancel", null)
            .create().apply {
                show()
                window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
            }
    }

    private fun sendReplyViaEndpoint(
        originalDigest: Digest,
        replyText: String,
        endpoint: EndpointConfig,
        tags: List<String>,
        fromThread: Boolean = false
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Get the source device from the original digest
                val sourceDevice = originalDigest.tags.firstOrNull { it.startsWith("from-") }
                    ?.removePrefix("from-") ?: "unknown"

                // Get the pod name from the current pod
                val podName = currentPod?.name ?: "unknown"

                // BUILD THE CORRECT REPLY MENTION FORMAT
                // @podname.probes-nodename.xyzpulseinfra.com.digestid.devicename
                val replyMention = "@$podName.probes-${endpoint.nodeName}.xyzpulseinfra.com.${originalDigest.id}.$sourceDevice"

                val fullContent = "$replyMention $replyText"

                Log.d("PodDetailFragment", "CORRECT Reply mention: $replyMention")

                // Build tag array properly for JSON
                val cleanDevice = endpoint.device.lowercase().replace(" ", "-")
                val tagArray = JSONArray().apply {
                    // Add selected tags
                    tags.forEach { put(it) }
                    // Add system tags
                    put("reply")
                    put(cleanDevice)
                    put("from-$cleanDevice")
                }

                val fileData = fullContent.toByteArray()
                val base64Content = Base64.encodeToString(fileData, Base64.NO_WRAP)

                // Build JSON properly with tags as array
                val jsonPayload = JSONObject().apply {
                    put("file", JSONObject().apply {
                        put("content", base64Content)
                        put("filename", "reply_${System.currentTimeMillis()}.txt")
                        put("content_type", "text/plain")
                    })
                    put("tags", tagArray)
                    put("device", endpoint.device)
                    put("context_prompt", "Reply to digest")
                }

                val client = OkHttpClient()
                val body = jsonPayload.toString().toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull())
                val url = "https://probes-${endpoint.nodeName}.xyzpulseinfra.com/api/probes/${endpoint.probeId}/run"

                val request = Request.Builder()
                    .url(url)
                    .header("X-PROBE-KEY", endpoint.probeKey)
                    .post(body)
                    .build()

                val response = client.newCall(request).execute()

                withContext(Dispatchers.Main) {
                    if (response.isSuccessful) {
                        Toast.makeText(requireContext(), "✅ Reply sent!", Toast.LENGTH_SHORT).show()
                        currentPod?.let { fetchDigests(it) }
                    } else {
                        val errorBody = response.body?.string()
                        Log.e("PodDetailFragment", "Reply failed: ${response.code} - $errorBody")
                        Toast.makeText(requireContext(), "❌ Reply failed: ${response.code}", Toast.LENGTH_LONG).show()
                    }
                }
            } catch (e: Exception) {
                Log.e("PodDetailFragment", "Reply error", e)
                withContext(Dispatchers.Main) {
                    Toast.makeText(requireContext(), "Reply failed: ${e.message}", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun showThreadDialog(digest: Digest) {
        // Find all replies using the CORRECT pattern
        val threadReplies = findAllReplies(digest.id)

        Log.d("PodDetailFragment", "Showing thread for ${digest.id}, found ${threadReplies.size} replies")

        if (threadReplies.isEmpty()) {
            Toast.makeText(requireContext(), "No replies yet", Toast.LENGTH_SHORT).show()
            return
        }

        val dialogView = ScrollView(requireContext()).apply {
            setPadding(16, 16, 16, 16)
        }

        val contentLayout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }

        // Add original post
        contentLayout.addView(createThreadCard(digest, 0, true))

        // Add separator
        contentLayout.addView(TextView(requireContext()).apply {
            text = "━━━ ${threadReplies.size} Replies ━━━"
            textSize = 12f
            setTextColor(0xFF666666.toInt())
            gravity = android.view.Gravity.CENTER
            setPadding(0, 16, 0, 16)
        })

        // Add all replies
        threadReplies.forEach { reply ->
            val depth = calculateDepth(digest.id, reply)
            contentLayout.addView(createThreadCard(reply, depth, false))
        }

        dialogView.addView(contentLayout)

        AlertDialog.Builder(requireContext())
            .setTitle("Thread View")
            .setView(dialogView)
            .setPositiveButton("Close", null)
            .show()
    }

    private fun findAllReplies(rootDigestId: String): List<Digest> {
        val allReplies = mutableListOf<Digest>()
        val processed = mutableSetOf<String>()
        val toProcess = mutableListOf(rootDigestId)

        while (toProcess.isNotEmpty()) {
            val currentId = toProcess.removeAt(0)
            if (processed.contains(currentId)) continue
            processed.add(currentId)

            // Find all direct replies using the CORRECT pattern
            // @podname.probes-nodename.xyzpulseinfra.com.DIGESTID.devicename
            val directReplies = allDigests.filter { digest ->
                digest.id != currentId &&
                        digest.id != rootDigestId &&
                        !processed.contains(digest.id) &&
                        digest.content.contains(".$currentId.")
            }

            allReplies.addAll(directReplies)
            toProcess.addAll(directReplies.map { it.id })
        }

        return allReplies.sortedBy { it.createdAt }
    }

    private fun calculateDepth(rootId: String, reply: Digest): Int {
        // Extract what this replies to using CORRECT pattern
        val replyPattern = Regex("@[^.]+\\.probes-[^.]+\\.xyzpulseinfra\\.com\\.([^.]+)\\.[^\\s]+")
        val match = replyPattern.find(reply.content)
        val parentId = match?.groupValues?.getOrNull(1)

        return when (parentId) {
            rootId -> 1
            null -> 1
            else -> {
                // Find the parent and calculate its depth
                val parent = allDigests.find { it.id == parentId }
                if (parent != null) {
                    calculateDepth(rootId, parent) + 1
                } else {
                    1
                }
            }
        }
    }

    private fun createThreadCard(
        digest: Digest,
        depth: Int,
        isOriginal: Boolean
    ): View {
        return LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(when {
                isOriginal -> 0xFF1A1A1D.toInt()
                depth % 2 == 1 -> 0xFF111113.toInt()
                else -> 0xFF0D0D0F.toInt()
            })
            val leftPadding = 16 + (depth * 20)
            setPadding(leftPadding, 12, 16, 12)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 2, 0, 2)
            }

            if (!isOriginal && depth > 0) {
                addView(TextView(requireContext()).apply {
                    text = "┗━ "
                    textSize = 10f
                    setTextColor(0xFF666666.toInt())
                })
            }

            // Author
            val fromTag = digest.tags.firstOrNull { it.startsWith("from-") }
            if (fromTag != null) {
                addView(TextView(requireContext()).apply {
                    text = fromTag.removePrefix("from-")
                    textSize = 12f
                    setTextColor(0xFF007AFF.toInt())
                    setTypeface(typeface, android.graphics.Typeface.BOLD)
                })
            }

            // Content
            addView(TextView(requireContext()).apply {
                text = digest.content
                textSize = if (isOriginal) 14f else 13f
                setTextColor(if (isOriginal) 0xFFFFFFFF.toInt() else 0xFFCCCCCC.toInt())
                setPadding(0, 4, 0, 8)
            })

            // Timestamp
            addView(TextView(requireContext()).apply {
                text = android.text.format.DateFormat.format("MMM d, h:mm a", digest.createdAt)
                textSize = 10f
                setTextColor(0xFF666666.toInt())
            })

            // Reply button
            addView(Button(requireContext()).apply {
                text = "↩️ Reply"
                textSize = 11f
                height = 36
                setBackgroundColor(0xFF222227.toInt())
                setTextColor(0xFF007AFF.toInt())
                setOnClickListener {
                    showReplyDialog(digest, fromThread = true)
                }
            })
        }
    }

    private fun shareDigest(digest: Digest) {
        val shareText = buildString {
            if (digest.title.isNotEmpty()) {
                appendLine(digest.title)
                appendLine()
            }
            appendLine(digest.content)
            if (digest.tags.isNotEmpty()) {
                appendLine()
                append(digest.tags.joinToString(" ") { "#$it" })
            }
        }

        val shareIntent = android.content.Intent().apply {
            action = android.content.Intent.ACTION_SEND
            type = "text/plain"
            putExtra(android.content.Intent.EXTRA_TEXT, shareText)
        }
        startActivity(android.content.Intent.createChooser(shareIntent, "Share digest"))
    }

    companion object {
        private const val ARG_POD_ID = "pod_id"
        private const val ARG_SELECTED_TAGS = "selected_tags"

        fun newInstance(podId: String, selectedTags: List<String>? = null) = PodDetailFragment().apply {
            arguments = Bundle().apply {
                putString(ARG_POD_ID, podId)
                selectedTags?.let {
                    putStringArrayList(ARG_SELECTED_TAGS, ArrayList(it))
                }
            }
        }
    }
}