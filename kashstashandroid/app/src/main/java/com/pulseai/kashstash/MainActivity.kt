package com.pulseai.kashstash

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.util.Base64
import android.util.Log
import android.view.Menu
import android.view.MenuItem
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.android.material.snackbar.Snackbar
import com.pulseai.kashstash.databinding.ActivityMainBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.time.Instant
import kotlinx.coroutines.delay

class MainActivity : AppCompatActivity() {

    companion object {
        private const val CAMERA_PERMISSION_REQUEST_CODE = 100
    }

    private lateinit var binding: ActivityMainBinding
    private val recentTagsManager = RecentTagsManager()
    private var tempPhotoUri: Uri? = null
    private var pendingCameraAction: (() -> Unit)? = null

    // Photo picker
    private val pickImageLauncher = registerForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let { showShareImageDialog(it) }
    }

    // QR image picker from gallery
    private val qrImagePicker = registerForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let { importQRConfig(it) }
    }

    // Camera launcher for QR capture
    private val takePictureLauncher = registerForActivityResult(
        ActivityResultContracts.TakePicture()
    ) { success: Boolean ->
        if (success) {
            tempPhotoUri?.let { importQRConfig(it) }
        } else {
            Toast.makeText(this, "Photo capture cancelled", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)

        updateCurrentInstancesText()
        setupButtons()
        handleShareIntent(intent)
    }

    private fun setupButtons() {
        // Go to Portal (NEW)
        findViewById<Button>(R.id.portalButton).setOnClickListener {
            val url = "https://pulseaiplatform.com"
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }

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

        // Import from QR
        findViewById<Button>(R.id.importQrButton).setOnClickListener {
            showImportChoiceDialog()
        }

        // Manage Endpoints
        findViewById<Button>(R.id.manageEndpointsButton).setOnClickListener {
            showManageEndpointsDialog()
        }

        // Manage Kash Files
        findViewById<Button>(R.id.manageKashFilesButton).setOnClickListener {
            showManageKashFilesDialog()
        }

        // Quick Note FAB
        findViewById<FloatingActionButton>(R.id.fab).setOnClickListener {
            showQuickNoteDialog()
        }

        // Photo FAB
        findViewById<FloatingActionButton?>(R.id.fab_photo)?.setOnClickListener {
            pickImageLauncher.launch("image/*")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
    }

    // ==== UI UPDATE METHODS ====
    private fun updateCurrentInstancesText() {
        val config = ConfigManager.load(this)

        // Update endpoint text
        val endpointTv = findViewById<TextView>(R.id.currentEndpointView)
        val endpoint = config.endpoints.getOrNull(config.lastUsedEndpoint)
        endpointTv.text = if (endpoint == null) "Endpoint: (none)" else "Endpoint: ${endpoint.name}"

        // Update Kash Files text - FIX THE INDEX ISSUE
        val kashFilesTv = findViewById<TextView>(R.id.currentKashFilesView)
        val kashFilesIndex = if (config.kashFiles.isEmpty()) -1 else config.lastUsedKashFiles
        val kashFiles = if (kashFilesIndex >= 0 && kashFilesIndex < config.kashFiles.size) {
            config.kashFiles[kashFilesIndex]
        } else {
            null
        }
        kashFilesTv.text = if (kashFiles == null) "Kash Files: (none)" else "Kash Files: ${kashFiles.name}"
    }

    // ==== ENDPOINT MANAGEMENT ====
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

        val options = arrayOf("Use this Endpoint", "Edit", "Delete")
        AlertDialog.Builder(this)
            .setTitle(selected.name)
            .setItems(options) { _, which ->
                when (which) {
                    0 -> switchEndpoint(index)
                    1 -> showAddEditEndpointDialog(selected, index)
                    2 -> deleteEndpoint(index)
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun switchEndpoint(index: Int) {
        val config = ConfigManager.load(this)
        val newConfig = config.copy(lastUsedEndpoint = index)
        ConfigManager.save(this, newConfig)
        updateCurrentInstancesText()
    }

    private fun deleteEndpoint(index: Int) {
        val config = ConfigManager.load(this)
        val ep = config.endpoints.getOrNull(index) ?: return

        AlertDialog.Builder(this)
            .setTitle("Delete Endpoint")
            .setMessage("Are you sure you want to delete '${ep.name}'?")
            .setPositiveButton("Delete") { _, _ ->
                val endpoints = config.endpoints.toMutableList()
                endpoints.removeAt(index)
                val newLast = if (config.lastUsedEndpoint >= endpoints.size)
                    endpoints.size - 1 else config.lastUsedEndpoint
                val newConfig = config.copy(
                    endpoints = endpoints,
                    lastUsedEndpoint = if (newLast < 0) 0 else newLast
                )
                ConfigManager.save(this, newConfig)
                updateCurrentInstancesText()
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

                val ep = EndpointConfig(
                    name, dev, key, node, probeId,
                    existing?.configDigestId ?: "",
                    existing?.configDigestTags ?: "agent-config",
                    existing?.configCacheMinutes ?: 5
                )

                val config = ConfigManager.load(this)
                val endpoints = config.endpoints.toMutableList()

                if (index >= 0 && index < endpoints.size) {
                    endpoints[index] = ep
                } else {
                    endpoints.add(ep)
                }

                val newConfig = config.copy(
                    endpoints = endpoints,
                    lastUsedEndpoint = if (index < 0) endpoints.size - 1 else config.lastUsedEndpoint
                )
                ConfigManager.save(this, newConfig)
                updateCurrentInstancesText()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ==== KASH FILES MANAGEMENT ====
    private fun showManageKashFilesDialog() {
        val config = ConfigManager.load(this)
        val names = config.kashFiles.map { it.name }
        val builder = AlertDialog.Builder(this)
        builder.setTitle("Kash Files Instances")

        if (names.isEmpty()) {
            builder.setMessage("No Kash Files instances configured.")
            builder.setPositiveButton("Add New") { _, _ -> showAddEditKashFilesDialog(null, -1) }
            builder.setNegativeButton("Close", null)
        } else {
            val options = names.mapIndexed { i, s ->
                if (i == config.lastUsedKashFiles) "✅ $s" else s
            }
            builder.setItems((options + "(Add New)").toTypedArray()) { _, which ->
                when {
                    which == names.size -> showAddEditKashFilesDialog(null, -1)
                    else -> showKashFilesOptions(which)
                }
            }
            builder.setNegativeButton("Close", null)
        }
        builder.show()
    }

    private fun showKashFilesOptions(index: Int) {
        val config = ConfigManager.load(this)
        val selected = config.kashFiles.getOrNull(index) ?: return

        val options = arrayOf("Use this Instance", "Edit", "Delete", "Test Connection")
        AlertDialog.Builder(this)
            .setTitle(selected.name)
            .setItems(options) { _, which ->
                when (which) {
                    0 -> switchKashFiles(index)
                    1 -> showAddEditKashFilesDialog(selected, index)
                    2 -> deleteKashFiles(index)
                    3 -> testKashFilesConnection(selected)
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun switchKashFiles(index: Int) {
        val config = ConfigManager.load(this)
        val newConfig = config.copy(lastUsedKashFiles = index)
        ConfigManager.save(this, newConfig)
        updateCurrentInstancesText()
    }

    private fun deleteKashFiles(index: Int) {
        val config = ConfigManager.load(this)
        val kf = config.kashFiles.getOrNull(index) ?: return

        AlertDialog.Builder(this)
            .setTitle("Delete Kash Files Instance")
            .setMessage("Are you sure you want to delete '${kf.name}'?")
            .setPositiveButton("Delete") { _, _ ->
                val kashFiles = config.kashFiles.toMutableList()
                kashFiles.removeAt(index)
                val newLast = if (config.lastUsedKashFiles >= kashFiles.size)
                    kashFiles.size - 1 else config.lastUsedKashFiles
                val newConfig = config.copy(
                    kashFiles = kashFiles,
                    lastUsedKashFiles = if (newLast < 0) 0 else newLast
                )
                ConfigManager.save(this, newConfig)
                updateCurrentInstancesText()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showAddEditKashFilesDialog(existing: KashFilesConfig?, index: Int) {
        val dialogView = layoutInflater.inflate(R.layout.dialog_add_edit_kash_files, null)
        val etName = dialogView.findViewById<EditText>(R.id.etKashName)
        val etUrl = dialogView.findViewById<EditText>(R.id.etKashUrl)
        val etKey = dialogView.findViewById<EditText>(R.id.etKashKey)
        val btnTest = dialogView.findViewById<Button>(R.id.btnTestConnection)

        if (existing != null) {
            etName.setText(existing.name)
            etUrl.setText(existing.url)
            etKey.setText(existing.key)
        }

        btnTest.setOnClickListener {
            val testConfig = KashFilesConfig(
                etName.text.toString(),
                etUrl.text.toString(),
                etKey.text.toString()
            )
            testKashFilesConnection(testConfig)
        }

        AlertDialog.Builder(this)
            .setTitle(if (existing == null) "Add Kash Files" else "Edit Kash Files")
            .setView(dialogView)
            .setPositiveButton("Save") { _, _ ->
                val name = etName.text.toString().trim()
                val url = etUrl.text.toString().trim()
                val key = etKey.text.toString().trim()

                if (name.isBlank() || url.isBlank() || key.isBlank()) {
                    Toast.makeText(this, "Please fill in all fields", Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }

                val kf = KashFilesConfig(name, url, key)
                val config = ConfigManager.load(this)
                val kashFiles = config.kashFiles.toMutableList()

                if (index >= 0 && index < kashFiles.size) {
                    kashFiles[index] = kf
                } else {
                    kashFiles.add(kf)
                }

                val newConfig = config.copy(
                    kashFiles = kashFiles,
                    lastUsedKashFiles = if (index < 0) kashFiles.size - 1 else config.lastUsedKashFiles
                )
                ConfigManager.save(this, newConfig)
                updateCurrentInstancesText()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun testKashFilesConnection(config: KashFilesConfig) {
        CoroutineScope(Dispatchers.Main).launch {
            val result = withContext(Dispatchers.IO) {
                KashFilesClient(config).testConnection()
            }
            val message = if (result) "✅ Connection successful!" else "❌ Connection failed"
            Toast.makeText(this@MainActivity, message, Toast.LENGTH_LONG).show()
        }
    }

    // ==== QR IMPORT WITH CAMERA PERMISSION ====
    private fun showImportChoiceDialog() {
        val options = arrayOf(
            "📷 Take Photo of QR Code",
            "🖼️ Select QR from Gallery",
            "⌨️ Manual Entry"
        )

        AlertDialog.Builder(this)
            .setTitle("Import Configuration")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> checkCameraPermissionAndCapture()
                    1 -> qrImagePicker.launch("image/*")
                    2 -> showManualImportChoice()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun checkCameraPermissionAndCapture() {
        when {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED -> {
                // Permission already granted
                captureQRPhoto()
            }
            ActivityCompat.shouldShowRequestPermissionRationale(
                this,
                Manifest.permission.CAMERA
            ) -> {
                // Show explanation dialog
                AlertDialog.Builder(this)
                    .setTitle("Camera Permission Required")
                    .setMessage("The camera is needed to scan QR codes. Please grant camera permission to use this feature.")
                    .setPositiveButton("Grant Permission") { _, _ ->
                        requestCameraPermission()
                    }
                    .setNegativeButton("Cancel", null)
                    .show()
            }
            else -> {
                // Request permission directly
                requestCameraPermission()
            }
        }
    }

    private fun requestCameraPermission() {
        pendingCameraAction = { captureQRPhoto() }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        when (requestCode) {
            CAMERA_PERMISSION_REQUEST_CODE -> {
                if (grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    // Permission granted, execute pending action
                    pendingCameraAction?.invoke()
                    pendingCameraAction = null
                } else {
                    // Permission denied
                    if (!ActivityCompat.shouldShowRequestPermissionRationale(
                            this,
                            Manifest.permission.CAMERA
                        )) {
                        // User selected "Don't ask again"
                        AlertDialog.Builder(this)
                            .setTitle("Camera Permission Denied")
                            .setMessage("Camera permission is required to scan QR codes. You can enable it in Settings > Apps > Kash Stash > Permissions.")
                            .setPositiveButton("OK", null)
                            .show()
                    } else {
                        // Just denied this time
                        Toast.makeText(
                            this,
                            "Camera permission denied. Cannot scan QR codes.",
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            }
        }
    }

    private fun captureQRPhoto() {
        try {
            val photoFile = File.createTempFile(
                "qr_scan_",
                ".jpg",
                getExternalFilesDir(Environment.DIRECTORY_PICTURES)
            )

            tempPhotoUri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                photoFile
            )

            takePictureLauncher.launch(tempPhotoUri)
        } catch (e: Exception) {
            Toast.makeText(this, "Failed to open camera: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun showManualImportChoice() {
        val options = arrayOf("Add Endpoint", "Add Kash Files")
        AlertDialog.Builder(this)
            .setTitle("Manual Configuration")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> showAddEditEndpointDialog(null, -1)
                    1 -> showAddEditKashFilesDialog(null, -1)
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun importQRConfig(imageUri: Uri) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Show progress indicator
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@MainActivity, "Reading QR code...", Toast.LENGTH_SHORT).show()
                }

                // Decode QR from image
                val decodedConfig = QRConfigImporter.decodeQRFromImage(imageUri, this@MainActivity)

                if (decodedConfig == null) {
                    withContext(Dispatchers.Main) {
                        AlertDialog.Builder(this@MainActivity)
                            .setTitle("QR Decode Failed")
                            .setMessage("Could not read QR code from image. Make sure the image contains a valid QR code.")
                            .setPositiveButton("OK", null)
                            .show()
                    }
                    return@launch
                }

                // Detect config type
                val configType = QRConfigImporter.detectConfigType(decodedConfig)

                withContext(Dispatchers.Main) {
                    when (configType) {
                        QRConfigImporter.ConfigType.KASH_FILES -> {
                            handleKashFilesImport(decodedConfig)
                        }
                        QRConfigImporter.ConfigType.MOBILE_ENDPOINT -> {
                            handleMobileEndpointImport(decodedConfig)
                        }
                        QRConfigImporter.ConfigType.DESKTOP_ENDPOINT -> {
                            handleDesktopEndpointImport(decodedConfig)
                        }
                        QRConfigImporter.ConfigType.UNKNOWN -> {
                            showUnknownQRDialog(decodedConfig)
                        }
                    }
                }

            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    AlertDialog.Builder(this@MainActivity)
                        .setTitle("Import Error")
                        .setMessage("Failed to import configuration: ${e.message}")
                        .setPositiveButton("OK", null)
                        .show()
                }
            }
        }
    }

    private fun handleKashFilesImport(config: Map<String, Any>) {
        val kashFiles = QRConfigImporter.extractKashFilesConfig(config)

        if (kashFiles == null || !QRConfigImporter.validateKashFilesConfig(kashFiles)) {
            AlertDialog.Builder(this)
                .setTitle("Invalid Configuration")
                .setMessage("The QR code doesn't contain a valid Kash Files configuration.")
                .setPositiveButton("OK", null)
                .show()
            return
        }

        // Test connection first
        CoroutineScope(Dispatchers.Main).launch {
            val connectionOk = withContext(Dispatchers.IO) {
                KashFilesClient(kashFiles).testConnection()
            }

            val statusMsg = if (connectionOk) {
                "✅ Connection successful to ${kashFiles.url}"
            } else {
                "⚠️ Could not connect to ${kashFiles.url}"
            }

            AlertDialog.Builder(this@MainActivity)
                .setTitle("Import Kash Files")
                .setMessage("""
                Add Kash Files instance?
                
                Name: ${kashFiles.name}
                URL: ${kashFiles.url}
                Key: ${kashFiles.key.take(10)}...
                
                $statusMsg
            """.trimIndent())
                .setPositiveButton("Add") { _, _ ->
                    addImportedKashFiles(kashFiles)
                }
                .setNegativeButton("Cancel", null)
                .show()
        }
    }

    private fun handleMobileEndpointImport(config: Map<String, Any>) {
        val endpoint = QRConfigImporter.convertMobileToDesktop(config)

        if (!QRConfigImporter.validateEndpointConfig(endpoint)) {
            AlertDialog.Builder(this)
                .setTitle("Invalid Configuration")
                .setMessage("The QR code doesn't contain a valid endpoint configuration.")
                .setPositiveButton("OK", null)
                .show()
            return
        }

        AlertDialog.Builder(this)
            .setTitle("Import Mobile Endpoint")
            .setMessage("""
            Add endpoint from mobile?
            
            Name: ${endpoint.name}
            Node: ${endpoint.nodeName}
            Device: ${endpoint.device}
            
            Note: This is a basic mobile config.
            Config digest settings can be added later.
        """.trimIndent())
            .setPositiveButton("Add") { _, _ ->
                addImportedEndpoint(endpoint)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun handleDesktopEndpointImport(config: Map<String, Any>) {
        val endpoint = QRConfigImporter.convertDesktopConfig(config)

        if (!QRConfigImporter.validateEndpointConfig(endpoint)) {
            AlertDialog.Builder(this)
                .setTitle("Invalid Configuration")
                .setMessage("The QR code doesn't contain a valid endpoint configuration.")
                .setPositiveButton("OK", null)
                .show()
            return
        }

        val hasDigestConfig = endpoint.configDigestId.isNotBlank()
        val digestInfo = if (hasDigestConfig) {
            "\n\nConfig Digest: ${endpoint.configDigestId}\nTags: ${endpoint.configDigestTags}"
        } else {
            ""
        }

        AlertDialog.Builder(this)
            .setTitle("Import Endpoint")
            .setMessage("""
            Add endpoint?
            
            Name: ${endpoint.name}
            Node: ${endpoint.nodeName}
            Device: ${endpoint.device}$digestInfo
        """.trimIndent())
            .setPositiveButton("Add") { _, _ ->
                addImportedEndpoint(endpoint)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showUnknownQRDialog(config: Map<String, Any>) {
        val configStr = config.entries.joinToString("\n") { "${it.key}: ${it.value}" }

        AlertDialog.Builder(this)
            .setTitle("Unknown QR Format")
            .setMessage("""
            This QR code doesn't match any known format.
            
            Contents:
            $configStr
        """.trimIndent())
            .setPositiveButton("OK", null)
            .show()
    }

    private fun addImportedEndpoint(endpoint: EndpointConfig) {
        val config = ConfigManager.load(this)

        // Check for duplicates
        val existingNames = config.endpoints.map { it.name }
        if (existingNames.contains(endpoint.name)) {
            AlertDialog.Builder(this)
                .setTitle("Duplicate")
                .setMessage("An endpoint named '${endpoint.name}' already exists. Add anyway?")
                .setPositiveButton("Add") { _, _ ->
                    saveImportedEndpoint(endpoint)
                }
                .setNegativeButton("Cancel", null)
                .show()
        } else {
            saveImportedEndpoint(endpoint)
        }
    }

    private fun saveImportedEndpoint(endpoint: EndpointConfig) {
        val config = ConfigManager.load(this)
        val newEndpoints = config.endpoints + endpoint
        val newConfig = config.copy(
            endpoints = newEndpoints,
            lastUsedEndpoint = newEndpoints.size - 1 // Switch to new endpoint
        )
        ConfigManager.save(this, newConfig)
        updateCurrentInstancesText()

        Snackbar.make(binding.root, "✅ Endpoint imported: ${endpoint.name}", Snackbar.LENGTH_LONG).show()
    }

    private fun addImportedKashFiles(kashFiles: KashFilesConfig) {
        val config = ConfigManager.load(this)

        // Check for duplicates
        val existingUrls = config.kashFiles.map { it.url }
        if (existingUrls.contains(kashFiles.url)) {
            AlertDialog.Builder(this)
                .setTitle("Duplicate")
                .setMessage("A Kash Files instance with URL '${kashFiles.url}' already exists.")
                .setPositiveButton("OK", null)
                .show()
            return
        }

        val newKashFiles = config.kashFiles + kashFiles
        val newConfig = config.copy(
            kashFiles = newKashFiles,
            lastUsedKashFiles = newKashFiles.size - 1 // Switch to new instance
        )
        ConfigManager.save(this, newConfig)
        updateCurrentInstancesText()

        Snackbar.make(binding.root, "✅ Kash Files imported: ${kashFiles.name}", Snackbar.LENGTH_LONG).show()
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

    private fun showShareTextDialog(sharedText: String) {
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL

        val sharedTextView = TextView(this)
        sharedTextView.text = sharedText
        sharedTextView.setPadding(0, 0, 0, 16)

        val noteInput = EditText(this)
        noteInput.hint = "Add your note (optional)"

        val contextInput = EditText(this)
        contextInput.hint = "AI Context (optional)"

        layout.setPadding(32, 24, 32, 0)
        layout.addView(sharedTextView)
        layout.addView(noteInput)
        layout.addView(contextInput)

        AlertDialog.Builder(this)
            .setTitle("Share to Kash Stash")
            .setView(layout)
            .setPositiveButton("Select Tags") { _, _ ->
                val userNote = noteInput.text.toString()
                val finalText = if (userNote.isBlank()) sharedText else "$sharedText\n\n$userNote"
                val context = contextInput.text.toString()

                showTagSelectionDialog { tags ->
                    uploadWithChoice(
                        finalText.toByteArray(),
                        "note_${System.currentTimeMillis()}.txt",
                        "text/plain",
                        tags,
                        context
                    )
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showShareImageDialog(imageUri: Uri) {
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL

        val contextInput = EditText(this)
        contextInput.hint = "AI Context (optional)"

        layout.setPadding(32, 24, 32, 0)
        layout.addView(contextInput)

        AlertDialog.Builder(this)
            .setTitle("Share Image to Kash Stash")
            .setView(layout)
            .setPositiveButton("Select Tags") { _, _ ->
                val context = contextInput.text.toString()

                showTagSelectionDialog { tags ->
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val inputStream = contentResolver.openInputStream(imageUri)
                            val imageBytes = inputStream?.readBytes() ?: throw Exception("Failed to read image")
                            inputStream.close()

                            withContext(Dispatchers.Main) {
                                uploadWithChoice(
                                    imageBytes,
                                    "image_${System.currentTimeMillis()}.jpg",
                                    "image/jpeg",
                                    tags,
                                    context
                                )
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                Snackbar.make(binding.root, "Failed to read image: ${e.message}", Snackbar.LENGTH_SHORT).show()
                            }
                        }
                    }
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showQuickNoteDialog() {
        val layout = LinearLayout(this)
        layout.orientation = LinearLayout.VERTICAL
        val noteInput = EditText(this)
        noteInput.hint = "Write a note…"
        layout.setPadding(32, 24, 32, 0)
        layout.addView(noteInput)

        AlertDialog.Builder(this)
            .setTitle("Quick Note")
            .setView(layout)
            .setPositiveButton("Select Tags") { _, _ ->
                val note = noteInput.text.toString()
                if (note.isNotBlank()) {
                    showTagSelectionDialog { tags ->
                        uploadWithChoice(
                            note.toByteArray(),
                            "note_${System.currentTimeMillis()}.txt",
                            "text/plain",
                            tags,
                            note
                        )
                    }
                } else {
                    Toast.makeText(this, "Note is empty.", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ==== TAG SELECTION ====
    private fun showTagSelectionDialog(callback: (String) -> Unit) {
        val config = ConfigManager.load(this)
        val recentTags = recentTagsManager.getRecentTagsList(config)

        val dialog = TagSelectionDialog(recentTags) { tags ->
            if (tags.isNotBlank()) {
                // Update and SAVE the config with recent tags
                val newConfig = recentTagsManager.updateRecentTags(tags, config)
                ConfigManager.save(this, newConfig)
            }
            callback(tags)
        }
        dialog.show(supportFragmentManager, "tags")
    }

    // ==== UPLOAD METHODS ====
    private fun uploadWithChoice(
        fileData: ByteArray,
        filename: String,
        contentType: String,
        tags: String,
        context: String
    ) {
        val config = ConfigManager.load(this)
        val hasEndpoint = config.endpoints.isNotEmpty()
        val hasKashFiles = config.kashFiles.isNotEmpty()

        when {
            !hasEndpoint && !hasKashFiles -> {
                Snackbar.make(binding.root, "No endpoint or Kash Files configured!", Snackbar.LENGTH_SHORT).show()
            }
            hasEndpoint && !hasKashFiles -> {
                // Only endpoint available
                uploadToEndpoint(fileData, filename, contentType, tags, context)
            }
            !hasEndpoint && hasKashFiles -> {
                // Only Kash Files available
                uploadToKashFiles(fileData, filename, contentType, tags, context)
            }
            else -> {
                // Both available, show choice dialog
                showUploadDestinationDialog(fileData, filename, contentType, tags, context)
            }
        }
    }

    private fun showUploadDestinationDialog(
        fileData: ByteArray,
        filename: String,
        contentType: String,
        tags: String,
        context: String
    ) {
        val dialogView = layoutInflater.inflate(R.layout.dialog_upload_destination, null)
        val radioGroup = dialogView.findViewById<RadioGroup>(R.id.destinationRadioGroup)

        val dialog = AlertDialog.Builder(this)
            .setView(dialogView)
            .create()

        dialogView.findViewById<Button>(R.id.btnConfirmDestination).setOnClickListener {
            when (radioGroup.checkedRadioButtonId) {
                R.id.radioEndpoint -> {
                    uploadToEndpoint(fileData, filename, contentType, tags, context)
                    dialog.dismiss()
                }
                R.id.radioKashFiles -> {
                    uploadToKashFiles(fileData, filename, contentType, tags, context)
                    dialog.dismiss()
                }
                R.id.radioBoth -> {
                    uploadToBoth(fileData, filename, contentType, tags, context)
                    dialog.dismiss()
                }
                else -> {
                    Toast.makeText(this, "Please select a destination", Toast.LENGTH_SHORT).show()
                }
            }
        }

        dialogView.findViewById<Button>(R.id.btnCancelDestination).setOnClickListener {
            dialog.dismiss()
        }

        dialog.show()
    }

    private fun uploadToEndpoint(
        fileData: ByteArray,
        filename: String,
        contentType: String,
        tags: String,
        context: String
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val config = ConfigManager.load(this@MainActivity)
                val ep = config.endpoints.getOrNull(config.lastUsedEndpoint)
                if (ep == null) {
                    withContext(Dispatchers.Main) {
                        Snackbar.make(binding.root, "No endpoint selected!", Snackbar.LENGTH_SHORT).show()
                    }
                    return@launch
                }

                val effectiveTags = appendDeviceToTags(tags, ep.device)
                val base64Content = Base64.encodeToString(fileData, Base64.NO_WRAP)

                val payload = """
                {
                  "file": {
                    "content": "$base64Content",
                    "filename": "$filename",
                    "content_type": "$contentType"
                  },
                  "tags": ${JSONObject.quote(effectiveTags)},
                  "device": ${JSONObject.quote(ep.device)},
                  "context_prompt": ${JSONObject.quote(context)}
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
                    "✅ Uploaded to endpoint!"
                } else {
                    "❌ Endpoint error: ${response.code}"
                }

                withContext(Dispatchers.Main) {
                    Snackbar.make(binding.root, message, Snackbar.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    Snackbar.make(binding.root, "Upload failed: ${e.message}", Snackbar.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun uploadToKashFiles(
        fileData: ByteArray,
        filename: String,
        contentType: String,
        tags: String,
        context: String
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            val config = ConfigManager.load(this@MainActivity)

            // Check if we have an endpoint for the link digest
            val hasEndpoint = config.endpoints.isNotEmpty()
            val kf = config.kashFiles.getOrNull(config.lastUsedKashFiles)

            if (kf == null) {
                Snackbar.make(binding.root, "No Kash Files selected!", Snackbar.LENGTH_SHORT).show()
                return@launch
            }

            val client = KashFilesClient(kf)
            val result = client.uploadFile(filename, fileData, contentType, tags, context)

            if (result.ok && result.download != null) {
                val fullUrl = "${kf.url}${result.download}"

                // If we have an endpoint, also create a digest with the link
                if (hasEndpoint) {
                    val isImage = contentType.startsWith("image/")

                    // Add filename as tag
                    val filenameTag = filename.substringBeforeLast('.')
                    val enhancedTags = if (tags.isBlank()) filenameTag else "$tags,$filenameTag"

                    val linkText = if (isImage) {
                        """
                    Image uploaded to Kash Files
                    File: $filename
                    Link: $fullUrl
                    
                    ${if (context.isNotBlank()) context else "View or download the image at the link above."}
                    """.trimIndent()
                    } else {
                        """
                    File uploaded to Kash Files
                    File: $filename
                    Link: $fullUrl
                    
                    ${if (context.isNotBlank()) context else "Download the file at the link above."}
                    """.trimIndent()
                    }

                    val linkFilename = "kf_link_${filename.substringBeforeLast('.')}_${Instant.now().epochSecond}.txt"

                    // Upload the link digest to endpoint
                    uploadToEndpoint(
                        linkText.toByteArray(),
                        linkFilename,
                        "text/plain",
                        enhancedTags,
                        linkText
                    )

                    Snackbar.make(
                        binding.root,
                        "✅ Uploaded to Kash Files + link saved!\nURL: $fullUrl",
                        Snackbar.LENGTH_LONG
                    ).show()
                } else {
                    // No endpoint, just show the Kash Files URL
                    Snackbar.make(
                        binding.root,
                        "✅ Uploaded to Kash Files!\nURL: $fullUrl",
                        Snackbar.LENGTH_LONG
                    ).show()
                }
            } else {
                Snackbar.make(binding.root, "❌ Upload failed: ${result.error}", Snackbar.LENGTH_SHORT).show()
            }
        }
    }

    private fun uploadToBoth(
        fileData: ByteArray,
        filename: String,
        contentType: String,
        tags: String,
        context: String
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            val config = ConfigManager.load(this@MainActivity)
            val kf = config.kashFiles.getOrNull(config.lastUsedKashFiles)

            if (kf == null) {
                Snackbar.make(binding.root, "No Kash Files selected!", Snackbar.LENGTH_SHORT).show()
                return@launch
            }

            // 1. Upload to Kash Files first
            val client = KashFilesClient(kf)
            val result = client.uploadFile(filename, fileData, contentType, tags, context)

            if (result.ok && result.download != null) {
                val fullUrl = "${kf.url}${result.download}"
                val isImage = contentType.startsWith("image/")

                // Add the filename (without extension) as a tag
                val filenameTag = filename.substringBeforeLast('.')
                val enhancedTags = if (tags.isBlank()) filenameTag else "$tags,$filenameTag"

                if (isImage) {
                    // For images: FIRST upload the link/caption, THEN the actual image
                    // This ensures caption appears below image in UI

                    // 1. Create and upload the link reference note FIRST
                    val linkNote = """
                    Image link for: $filename
                    Kash Files URL: $fullUrl
                    
                    This image has been processed by AI captioning (see digest above).
                    The full resolution image is available at the link above.
                """.trimIndent()

                    val linkFilename = "link_${filename.substringBeforeLast('.')}_${Instant.now().epochSecond}.txt"

                    uploadToEndpoint(
                        linkNote.toByteArray(),
                        linkFilename,
                        "text/plain",
                        enhancedTags,  // Use enhanced tags with filename
                        linkNote
                    )

                    // 2. Small delay to ensure order
                    kotlinx.coroutines.delay(100)

                    // 3. Upload the ACTUAL IMAGE SECOND for AI processing
                    uploadToEndpoint(fileData, filename, contentType, enhancedTags, context)

                    Snackbar.make(
                        binding.root,
                        "✅ Image uploaded to both!\n→ Full image for AI processing\n→ Kash Files link saved",
                        Snackbar.LENGTH_LONG
                    ).show()
                } else {
                    // For non-images: Just create a link reference
                    val captionText = """
                    File: $filename
                    Link: $fullUrl
                    
                    $context
                """.trimIndent()

                    val captionFilename = "linked_${filename.substringBeforeLast('.')}_${Instant.now().epochSecond}.txt"

                    uploadToEndpoint(
                        captionText.toByteArray(),
                        captionFilename,
                        "text/plain",
                        enhancedTags,
                        captionText
                    )

                    Snackbar.make(
                        binding.root,
                        "✅ File uploaded!\n→ Kash Files (full file)\n→ Endpoint (link reference)",
                        Snackbar.LENGTH_LONG
                    ).show()
                }
            } else {
                Snackbar.make(binding.root, "❌ Kash Files upload failed: ${result.error}", Snackbar.LENGTH_SHORT).show()
            }
        }
    }

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

    // ==== MENU ====
    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.menu_main, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_import_qr -> {
                showImportChoiceDialog()
                true
            }
            R.id.action_manage_endpoints -> {
                showManageEndpointsDialog()
                true
            }
            R.id.action_manage_kash_files -> {
                showManageKashFilesDialog()
                true
            }
            R.id.action_settings -> true
            else -> super.onOptionsItemSelected(item)
        }
    }
}