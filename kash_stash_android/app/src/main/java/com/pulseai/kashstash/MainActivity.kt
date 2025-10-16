package com.pulseai.kashstash

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Base64
import android.util.Log
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.android.material.snackbar.Snackbar
import com.pulseai.kashstash.databinding.ActivityMainBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import android.view.Menu
import android.view.MenuItem

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    // Photo FAB uses this
    private val pickImageLauncher = registerForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let { showShareImageDialog(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        updateCurrentEndpointText(ConfigManager.load(this))
        // Go to Pulse Node
        findViewById<Button>(R.id.goToNodeButton).setOnClickListener {
            val config = ConfigManager.load(this)
            val nodeName = config.endpoints.getOrNull(config.lastUsedEndpoint)?.nodeName
            if (!nodeName.isNullOrBlank()) {
                val url = "https://pulse-$nodeName.xyzpulseinfra.com"
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            } else {
                Snackbar.make(binding.root, "No node selected!", Snackbar.LENGTH_SHORT).show()
            }
        }
// Go to Blog
        findViewById<Button>(R.id.blogButton).setOnClickListener {
            val url = "https://blog.pulseaiplatform.com"
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }

        // Manage Endpoints
        findViewById<Button>(R.id.manageEndpointsButton).setOnClickListener {
            showManageEndpointsDialog()
        }

        findViewById<FloatingActionButton>(R.id.fab).setOnClickListener {
            showQuickNoteDialog()
        }

        // Handle the photo FAB if present in your XML
        findViewById<FloatingActionButton?>(R.id.fab_photo)?.setOnClickListener {
            pickImageLauncher.launch("image/*")
        }

        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
    }

    // ---- Endpoint Management UI ----
    private fun updateCurrentEndpointText(config: KashStashConfig) {
        val tv = findViewById<TextView>(R.id.currentEndpointView)
        val ep = config.endpoints.getOrNull(config.lastUsedEndpoint)
        tv.text = if (ep == null) "Endpoint: none" else "Endpoint: ${ep.name}"
    }

    private fun showManageEndpointsDialog() {
        val config = ConfigManager.load(this)
        val names = config.endpoints.map { it.name }
        val builder = AlertDialog.Builder(this)
        builder.setTitle("Endpoints")
        if (names.isEmpty()) {
            builder.setMessage("No endpoints configured.")
            builder.setPositiveButton("Add New") { _, _ -> showAddEditEndpointDialog(null, -1) }
            builder.setNegativeButton("Close", null)
        } else {
            val options = names.mapIndexed { i, s ->
                if (i == config.lastUsedEndpoint) "✅ $s" else s
            }
            builder.setItems((options + "(Add New)").toTypedArray()) { _, which ->
                when {
                    which == names.size -> showAddEditEndpointDialog(null, -1)
                    else -> showEndpointOptions(which)
                }
            }
            builder.setNegativeButton("Close", null)
        }
        builder.show()
    }

    private fun showEndpointOptions(index: Int) {
        val config = ConfigManager.load(this)
        val selected = config.endpoints.getOrNull(index) ?: return

        val options = arrayOf(
            "Use this Endpoint",
            "Edit",
            "Delete"
        )
        AlertDialog.Builder(this)
            .setTitle(selected.name)
            .setItems(options) { _, which ->
                when (which) {
                    0 -> { // Switch
                        val newConfig = config.copy(lastUsedEndpoint = index)
                        ConfigManager.save(this, newConfig)
                        updateCurrentEndpointText(newConfig)
                    }
                    1 -> showAddEditEndpointDialog(selected, index)
                    2 -> showDeleteEndpointDialog(index)
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showAddEditEndpointDialog(existing: EndpointConfig?, index: Int) {
        val dialogView = layoutInflater.inflate(R.layout.dialog_add_edit_endpoint, null)
        val etName = dialogView.findViewById<EditText>(R.id.etName)
        val etDevice = dialogView.findViewById<EditText>(R.id.etDevice)
        val etProbeKey = dialogView.findViewById<EditText>(R.id.etProbeKey)
        val etNodeName = dialogView.findViewById<EditText>(R.id.etNodeName)
        val etProbeId = dialogView.findViewById<EditText>(R.id.etProbeId)
        if (existing != null) {
            etName.setText(existing.name)
            etDevice.setText(existing.device)
            etProbeKey.setText(existing.probeKey)
            etNodeName.setText(existing.nodeName)
            etProbeId.setText(existing.probeId)
        } else {
            etProbeId.setText("29")
        }
        AlertDialog.Builder(this)
            .setTitle(if (existing == null) "Add Endpoint" else "Edit Endpoint")
            .setView(dialogView)
            .setPositiveButton("Save") { _, _ ->
                val name = etName.text.toString().trim()
                val dev = etDevice.text.toString().trim()
                val key = etProbeKey.text.toString().trim()
                val node = etNodeName.text.toString().trim()
                val probeId = etProbeId.text.toString().trim()
                if (name.isBlank() || key.isBlank() || node.isBlank() || probeId.isBlank()) {
                    Toast.makeText(this, "Please fill in all required fields", Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }
                val ep = EndpointConfig(name, dev, key, node, probeId)
                val config = ConfigManager.load(this)
                val endpoints = config.endpoints.toMutableList()
                if (index >= 0 && index < endpoints.size) {
                    endpoints[index] = ep
                } else {
                    endpoints.add(ep)
                }
                val newConfig = config.copy(
                    endpoints = endpoints,
                    lastUsedEndpoint = endpoints.size - 1
                )
                ConfigManager.save(this, newConfig)
                updateCurrentEndpointText(newConfig)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showDeleteEndpointDialog(index: Int) {
        val config = ConfigManager.load(this)
        val ep = config.endpoints.getOrNull(index) ?: return
        AlertDialog.Builder(this)
            .setTitle("Delete Endpoint")
            .setMessage("Are you sure you want to delete '${ep.name}'?")
            .setPositiveButton("Delete") { _, _ ->
                val endpoints = config.endpoints.toMutableList()
                endpoints.removeAt(index)
                val newLast = if (config.lastUsedEndpoint >= endpoints.size) endpoints.size - 1 else config.lastUsedEndpoint
                val newConfig = config.copy(
                    endpoints = endpoints,
                    lastUsedEndpoint = if (newLast < 0) 0 else newLast
                )
                ConfigManager.save(this, newConfig)
                updateCurrentEndpointText(newConfig)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ==== SHARING/UPLOAD LOGIC ====
    private fun handleShareIntent(intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SEND -> {
                when {
                    intent.type == "text/plain" -> {
                        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                        if (!sharedText.isNullOrBlank()) {
                            showShareTextDialog(sharedText)
                        }
                    }
                    intent.type?.startsWith("image/") == true -> {
                        val imageUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                        if (imageUri != null) {
                            showShareImageDialog(imageUri)
                        }
                    }
                }
            }
        }
    }

    // --- For text share intents: Let user add an extra note, tags, context ---
    private fun showShareTextDialog(sharedText: String) {
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL

        val sharedTextView = TextView(this)
        sharedTextView.text = sharedText
        sharedTextView.setPadding(0, 0, 0, 16)

        val noteInput = EditText(this)
        noteInput.hint = "Add your note (optional)"

        val tagsInput = EditText(this)
        tagsInput.hint = "Tags (comma separated)"

        val contextInput = EditText(this)
        contextInput.hint = "AI Context (optional)"

        layout.setPadding(32, 24, 32, 0)
        layout.addView(sharedTextView)
        layout.addView(noteInput)
        layout.addView(tagsInput)
        layout.addView(contextInput)

        AlertDialog.Builder(this)
            .setTitle("Share to Kash Stash")
            .setView(layout)
            .setPositiveButton("Send") { _, _ ->
                val userNote = noteInput.text.toString()
                val finalText = if (userNote.isBlank()) sharedText else "$sharedText\n\n$userNote"
                postToServer(finalText, tagsInput.text.toString(), contextInput.text.toString())
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // --- For image share intents: let user add tags, context ---
    private fun showShareImageDialog(imageUri: Uri) {
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL

        val tagsInput = EditText(this)
        tagsInput.hint = "Tags (comma separated)"

        val contextInput = EditText(this)
        contextInput.hint = "AI Context (optional)"

        layout.setPadding(32, 24, 32, 0)
        layout.addView(tagsInput)
        layout.addView(contextInput)

        AlertDialog.Builder(this)
            .setTitle("Share Image to Kash Stash")
            .setView(layout)
            .setPositiveButton("Send") { _, _ ->
                postImageToServer(imageUri, tagsInput.text.toString(), contextInput.text.toString())
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ==== QUICK NOTE DIALOG ====
    private fun showQuickNoteDialog() {
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL
        val noteInput = EditText(this)
        noteInput.hint = "Write a note…"
        val tagsInput = EditText(this)
        tagsInput.hint = "Tags (comma separated)"
        layout.setPadding(32, 24, 32, 0)
        layout.addView(noteInput)
        layout.addView(tagsInput)
        AlertDialog.Builder(this)
            .setTitle("Quick Note")
            .setView(layout)
            .setPositiveButton("Send") { _, _ ->
                val note = noteInput.text.toString()
                val tags = tagsInput.text.toString()
                if (note.isNotBlank()) {
                    postToServer(note, tags)
                } else {
                    Toast.makeText(this, "Note is empty.", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ==== HTTP Upload: text (with base64) AND device tag always ====
    private fun postToServer(note: String, tags: String = "", contextPrompt: String = "") {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val config = ConfigManager.load(this@MainActivity)
                val ep = config.endpoints.getOrNull(config.lastUsedEndpoint)
                if (ep == null) {
                    runOnUiThread {
                        Snackbar.make(binding.root, "No endpoint selected!", Snackbar.LENGTH_SHORT).show()
                    }
                    return@launch
                }
                val effectiveTags = appendDeviceToTags(tags, ep.device)
                val noteBytes = note.toByteArray(Charsets.UTF_8)
                val base64Content = Base64.encodeToString(noteBytes, Base64.NO_WRAP)
                val payload = """
                {
                  "file": {
                    "content": "$base64Content",
                    "filename": "note_${System.currentTimeMillis()}.txt",
                    "content_type": "text/plain"
                  },
                  "tags": ${JSONObject.quote(effectiveTags)},
                  "device": ${JSONObject.quote(ep.device)},
                  "context_prompt": ${JSONObject.quote(contextPrompt)}
                }
                """.trimIndent()
                val client = OkHttpClient()
                val JSON = "application/json; charset=utf-8".toMediaTypeOrNull()
                val body = payload.toRequestBody(JSON)
                val url = "https://probes-${ep.nodeName}.xyzpulseinfra.com/api/probes/${ep.probeId}/run"
                val request = Request.Builder()
                    .url(url)
                    .header("X-PROBE-KEY", ep.probeKey)
                    .post(body)
                    .build()
                val response = client.newCall(request).execute()
                val responseBody = response.body?.string() ?: ""
                val message = if (response.isSuccessful) {
                    "Shared data sent!\n$responseBody"
                } else {
                    "Server error: ${response.code}\n$responseBody"
                }
                Log.d("Kash Stash", "Server response: $responseBody")
                runOnUiThread {
                    Snackbar.make(binding.root, message, Snackbar.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                Log.e("Kash Stash", "Share failed: ${e.message}", e)
                runOnUiThread {
                    Snackbar.make(binding.root, "Share failed: ${e.message}", Snackbar.LENGTH_SHORT).show()
                }
            }
        }
    }

    // ==== HTTP Upload: image (with base64), tags, context, device always ====
    private fun postImageToServer(imageUri: Uri, tags: String, contextPrompt: String) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val config = ConfigManager.load(this@MainActivity)
                val ep = config.endpoints.getOrNull(config.lastUsedEndpoint)
                if (ep == null) {
                    runOnUiThread {
                        Snackbar.make(binding.root, "No endpoint selected!", Snackbar.LENGTH_SHORT).show()
                    }
                    return@launch
                }
                val effectiveTags = appendDeviceToTags(tags, ep.device)
                val inputStream = contentResolver.openInputStream(imageUri)
                val imageBytes = inputStream?.readBytes() ?: throw Exception("Failed to read image")
                inputStream.close()
                val base64Content = Base64.encodeToString(imageBytes, Base64.NO_WRAP)
                val payload = """
                {
                  "file": {
                    "content": "$base64Content",
                    "filename": "image_${System.currentTimeMillis()}.jpg",
                    "content_type": "image/jpeg"
                  },
                  "tags": ${JSONObject.quote(effectiveTags)},
                  "device": ${JSONObject.quote(ep.device)},
                  "context_prompt": ${JSONObject.quote(contextPrompt)}
                }
                """.trimIndent()
                val client = OkHttpClient()
                val JSON = "application/json; charset=utf-8".toMediaTypeOrNull()
                val body = payload.toRequestBody(JSON)
                val url = "https://probes-${ep.nodeName}.xyzpulseinfra.com/api/probes/${ep.probeId}/run"
                val request = Request.Builder()
                    .url(url)
                    .header("X-PROBE-KEY", ep.probeKey)
                    .post(body)
                    .build()
                val response = client.newCall(request).execute()
                val responseBody = response.body?.string() ?: ""
                val message = if (response.isSuccessful) {
                    "Image sent!\n$responseBody"
                } else {
                    "Server error: ${response.code}\n$responseBody"
                }
                Log.d("Kash Stash", "Server response (image): $responseBody")
                runOnUiThread {
                    Snackbar.make(binding.root, message, Snackbar.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                Log.e("Kash Stash", "Image share failed: ${e.message}", e)
                runOnUiThread {
                    Snackbar.make(binding.root, "Image share failed: ${e.message}", Snackbar.LENGTH_SHORT).show()
                }
            }
        }
    }

    // Helper: add device as tag (not duplicate)
    private fun appendDeviceToTags(tags: String, device: String?): String {
        val normalizedDevice = device?.trim()
        if (!normalizedDevice.isNullOrBlank()) {
            val tagList = tags.split(',').map { it.trim() }.filter { it.isNotEmpty() }
            if (tagList.any { it.equals(normalizedDevice, ignoreCase = true) }) {
                return tags
            }
            return (tagList + normalizedDevice).joinToString(",")
        }
        return tags
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.menu_main, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_settings -> true
            else -> super.onOptionsItemSelected(item)
        }
    }
}