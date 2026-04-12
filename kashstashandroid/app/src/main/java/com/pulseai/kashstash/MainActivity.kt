package com.pulseai.kashstash

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.util.Base64
import android.util.Log
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.google.android.material.snackbar.Snackbar
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.pulseai.kashstash.databinding.ActivityMainBinding
import com.pulseai.kashstash.pods.models.Digest
import com.pulseai.kashstash.pods.models.PodConfig
import com.pulseai.kashstash.pods.services.BackgroundSyncManager
import com.pulseai.kashstash.pods.services.MultiPodAggregator
import com.pulseai.kashstash.pods.services.NotificationManager
import com.pulseai.kashstash.pods.services.NotificationPermissionHelper
import com.pulseai.kashstash.pods.services.PodClient
import com.pulseai.kashstash.pods.storage.PodDatabase
import com.pulseai.kashstash.pods.storage.PodPreferences
import com.pulseai.kashstash.pods.storage.PodRepository
import com.pulseai.kashstash.pods.ui.PodsListFragment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.Date

class MainActivity : AppCompatActivity() {

    companion object {
        private const val CAMERA_PERMISSION_REQUEST_CODE = 100
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 101
    }

    private lateinit var binding: ActivityMainBinding
    private lateinit var repository: PodRepository
    private lateinit var homeContent: View
    private lateinit var fragmentContainer: View

    // MANAGERS
    private val recentTagsManager = RecentTagsManager()
    private lateinit var savedPromptsManager: SavedPromptsManager

    private var tempPhotoUri: Uri? = null
    private var pendingCameraAction: (() -> Unit)? = null

    // Notification permission launcher
    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            Toast.makeText(this, "Notifications enabled!", Toast.LENGTH_SHORT).show()
            BackgroundSyncManager.syncDeviceNamesFromEndpoints(this)
        } else {
            Toast.makeText(this, "Notifications disabled. You can enable them in Settings.", Toast.LENGTH_LONG).show()
        }
    }

    // QR image picker from gallery (Config Import)
    private val qrImagePicker = registerForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let { importQRConfig(it) }
    }

    // Camera launcher for QR capture (Config Import)
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

        // Initialize Managers
        savedPromptsManager = SavedPromptsManager(this)

        // Initialize Pods repository
        val database = PodDatabase.getDatabase(this)
        repository = PodRepository(database.podDao())

        homeContent = findViewById(R.id.homeContent)
        fragmentContainer = findViewById(R.id.fragment_container)

        updateCurrentInstancesText()
        setupButtons()
        setupPodsButtons()
        updatePodsDisplay()
        handleShareIntent(intent)

        checkNotificationPermission()
        BackgroundSyncManager.syncDeviceNamesFromEndpoints(this)

        supportFragmentManager.addOnBackStackChangedListener {
            updateUIVisibility()
        }
    }

    private fun checkNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!NotificationPermissionHelper.isPermissionGranted(this)) {
                if (NotificationPermissionHelper.shouldShowRationale(this)) {
                    AlertDialog.Builder(this)
                        .setTitle("Enable Notifications")
                        .setMessage("Enable notifications to get alerts when someone replies to your posts or when new content is posted to your pods.")
                        .setPositiveButton("Enable") { _, _ ->
                            NotificationPermissionHelper.requestPermission(notificationPermissionLauncher)
                        }
                        .setNegativeButton("Not Now", null)
                        .show()
                } else {
                    NotificationPermissionHelper.requestPermission(notificationPermissionLauncher)
                }
            }
        }
    }

    private fun setupButtons() {
        findViewById<Button>(R.id.portalButton).setOnClickListener {
            val url = "https://pulseaiplatform.com"
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }

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

        findViewById<Button>(R.id.blogButton).setOnClickListener {
            val url = "https://blog.pulseaiplatform.com"
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }

        // Import Config QR
        findViewById<Button>(R.id.importQrButton).setOnClickListener {
            showImportChoiceDialog()
        }

        // NEW: Scan Generic Barcode/QR to Text Share
        findViewById<Button>(R.id.scanGenericQrButton).setOnClickListener {
            startGenericBarcodeScan()
        }

        findViewById<Button>(R.id.manageEndpointsButton).setOnClickListener {
            showManageEndpointsDialog()
        }

        findViewById<Button>(R.id.manageKashFilesButton).setOnClickListener {
            showManageKashFilesDialog()
        }
    }

    private fun setupPodsButtons() {
        findViewById<Button>(R.id.managePodsButton).setOnClickListener {
            navigateToPods()
        }
    }

    private fun navigateToPods() {
        val fragment = PodsListFragment.newInstance()
        supportFragmentManager.beginTransaction()
            .replace(R.id.fragment_container, fragment)
            .addToBackStack("pods")
            .commit()

        fragmentContainer.visibility = View.VISIBLE
        homeContent.visibility = View.GONE
    }

    private fun updateUIVisibility() {
        val isFragmentShown = supportFragmentManager.backStackEntryCount > 0
        fragmentContainer.visibility = if (isFragmentShown) View.VISIBLE else View.GONE
        homeContent.visibility = if (isFragmentShown) View.GONE else View.VISIBLE
    }

    private fun updatePodsDisplay() {
        lifecycleScope.launch {
            repository.getAllPods().collect { pods ->
                val podsText = findViewById<TextView>(R.id.currentPodsView)
                val activeCount = pods.count { it.isActive }

                podsText.text = when {
                    pods.isEmpty() -> "Pods: (none)"
                    activeCount == 0 -> "Pods: ${pods.size} configured"
                    else -> "Pods: ${pods.size} configured ($activeCount active)"
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
    }

    override fun onBackPressed() {
        if (supportFragmentManager.backStackEntryCount > 0) {
            supportFragmentManager.popBackStack()
        } else {
            super.onBackPressed()
        }
    }

    override fun onResume() {
        super.onResume()
    }

    // ==== UI UPDATE METHODS ====
    private fun updateCurrentInstancesText() {
        val config = ConfigManager.load(this)

        val endpointTv = findViewById<TextView>(R.id.currentEndpointView)
        val endpoint = config.endpoints.getOrNull(config.lastUsedEndpoint)
        endpointTv.text = if (endpoint == null) "Endpoint: (none)" else "Endpoint: ${endpoint.name}"

        val kashFilesTv = findViewById<TextView>(R.id.currentKashFilesView)
        val kashFilesIndex = if (config.kashFiles.isEmpty()) -1 else config.lastUsedKashFiles
        val kashFiles = if (kashFilesIndex >= 0 && kashFilesIndex < config.kashFiles.size) {
            config.kashFiles[kashFilesIndex]
        } else {
            null
        }
        kashFilesTv.text = if (kashFiles == null) "Kash Files: (none)" else "Kash Files: ${kashFiles.name}"

        try {
            BackgroundSyncManager.syncDeviceNamesFromEndpoints(this)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error syncing device names", e)
        }
    }

    // ==== GENERIC BARCODE SCANNER ====
    private fun startGenericBarcodeScan() {
        val scanner = GmsBarcodeScanning.getClient(this)

        scanner.startScan()
            .addOnSuccessListener { barcode ->
                val rawValue = barcode.rawValue
                if (rawValue != null) {
                    // Pipe result directly to the Share Text/Link dialog
                    showCaptionDialogForLink(rawValue)
                } else {
                    Toast.makeText(this, "Could not read code value", Toast.LENGTH_SHORT).show()
                }
            }
            .addOnFailureListener { e ->
                Log.d("Scan", "Scan failed or canceled: ${e.message}")
            }
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

    // ==== QR IMPORT WITH CAMERA PERMISSION (For Config) ====
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
                captureQRPhoto()
            }
            ActivityCompat.shouldShowRequestPermissionRationale(
                this,
                Manifest.permission.CAMERA
            ) -> {
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
                    pendingCameraAction?.invoke()
                    pendingCameraAction = null
                } else {
                    if (!ActivityCompat.shouldShowRequestPermissionRationale(
                            this,
                            Manifest.permission.CAMERA
                        )) {
                        AlertDialog.Builder(this)
                            .setTitle("Camera Permission Denied")
                            .setMessage("Camera permission is required to scan QR codes. You can enable it in Settings > Apps > Kash Stash > Permissions.")
                            .setPositiveButton("OK", null)
                            .show()
                    } else {
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
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@MainActivity, "Reading QR code...", Toast.LENGTH_SHORT).show()
                }

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

                val configType = QRConfigImporter.detectConfigType(decodedConfig)

                withContext(Dispatchers.Main) {
                    when (configType) {
                        QRConfigImporter.ConfigType.POD_CONFIG -> {
                            handlePodImport(decodedConfig)
                        }
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

    private fun handlePodImport(config: Map<String, Any>) {
        val podConfig = QRConfigImporter.extractPodConfig(config)

        if (podConfig == null || !QRConfigImporter.validatePodConfig(podConfig)) {
            AlertDialog.Builder(this)
                .setTitle("Invalid Configuration")
                .setMessage("The QR code doesn't contain a valid Pod configuration.")
                .setPositiveButton("OK", null)
                .show()
            return
        }

        val tagsPreview = if (podConfig.cachedTags.isNotEmpty()) {
            podConfig.cachedTags.joinToString(", ")
        } else {
            "(none)"
        }

        AlertDialog.Builder(this)
            .setTitle("Import Pod")
            .setMessage("""
                Add Pod?
                
                Name: ${podConfig.name}
                URL: ${podConfig.entranceNodeUrl}
                Key: ${podConfig.presharedKey.take(10)}...
                Tags: $tagsPreview
            """.trimIndent())
            .setPositiveButton("Add") { _, _ ->
                QRConfigImporter.importPodConfig(this, podConfig)
                Snackbar.make(binding.root, "✅ Pod imported: ${podConfig.name}", Snackbar.LENGTH_LONG).show()
                updatePodsDisplay()
            }
            .setNegativeButton("Cancel", null)
            .show()
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
            lastUsedEndpoint = newEndpoints.size - 1
        )
        ConfigManager.save(this, newConfig)
        updateCurrentInstancesText()

        Snackbar.make(binding.root, "✅ Endpoint imported: ${endpoint.name}", Snackbar.LENGTH_LONG).show()
    }

    private fun addImportedKashFiles(kashFiles: KashFilesConfig) {
        val config = ConfigManager.load(this)

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
            lastUsedKashFiles = newKashFiles.size - 1
        )
        ConfigManager.save(this, newConfig)
        updateCurrentInstancesText()

        Snackbar.make(binding.root, "✅ Kash Files imported: ${kashFiles.name}", Snackbar.LENGTH_LONG).show()
    }

    // ==== SHARING/UPLOAD LOGIC ====
    private fun handleShareIntent(intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val type = intent.type ?: return

                when {
                    type == "text/plain" -> {
                        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                        if (!sharedText.isNullOrBlank()) {
                            handleSharedLink(sharedText)
                        }
                    }
                    type.startsWith("image/") -> {
                        val imageUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                        if (imageUri != null) {
                            handleSharedImage(imageUri)
                        }
                    }
                    else -> {
                        // Handle other file types (raw files)
                        val fileUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                        if (fileUri != null) {
                            handleSharedRawFile(fileUri, type)
                        }
                    }
                }
            }
        }
    }

    // ==== SHARED LINK WORKFLOW ====
    private fun handleSharedLink(linkText: String) {
        val config = ConfigManager.load(this)
        val hasEndpoint = config.endpoints.isNotEmpty()

        if (!hasEndpoint) {
            Snackbar.make(binding.root, "No endpoint configured!", Snackbar.LENGTH_LONG).show()
            return
        }

        // Skip destination choice, go straight to caption dialog
        showCaptionDialogForLink(linkText)
    }

    private fun showCaptionDialogForLink(linkText: String) {
        val dialogView = layoutInflater.inflate(R.layout.dialog_share_content, null)
        val titleView = dialogView.findViewById<TextView>(R.id.dialogTitle)
        val previewView = dialogView.findViewById<TextView>(R.id.sharedContentPreview)

        // AUTOCOMPLETE FOR TEXT
        val captionInput = dialogView.findViewById<AutoCompleteTextView>(R.id.captionInput)

        val tagsDisplay = dialogView.findViewById<TextView>(R.id.selectedTagsDisplay)
        val btnSelectTags = dialogView.findViewById<Button>(R.id.btnSelectTags)
        val btnCancel = dialogView.findViewById<Button>(R.id.btnCancelShare)
        val btnConfirm = dialogView.findViewById<Button>(R.id.btnConfirmShare)

        titleView.text = "Share Link / Text"
        previewView.text = linkText
        previewView.visibility = android.view.View.VISIBLE

        // SETUP PROMPTS
        val savedPrompts = savedPromptsManager.getPrompts()
        val adapter = ArrayAdapter(this, android.R.layout.simple_dropdown_item_1line, savedPrompts)
        captionInput.setAdapter(adapter)
        captionInput.threshold = 1

        var selectedTags = ""

        btnSelectTags.setOnClickListener {
            showTagSelectionDialog { tags ->
                selectedTags = tags
                tagsDisplay.text = if (tags.isBlank()) "Tags: (none)" else "Tags: $tags"
            }
        }

        val dialog = AlertDialog.Builder(this)
            .setView(dialogView)
            .create()

        btnCancel.setOnClickListener {
            dialog.dismiss()
        }

        btnConfirm.setOnClickListener {
            val caption = captionInput.text.toString().trim()

            // SAVE PROMPT
            savedPromptsManager.savePrompt(caption)

            // Format: link text, newline, then caption (if provided)
            val finalText = if (caption.isBlank()) {
                linkText
            } else {
                "$linkText\n\n$caption"
            }

            dialog.dismiss()

            val filename = "link_${System.currentTimeMillis()}.txt"
            val fileData = finalText.toByteArray()

            // Only upload to endpoint
            uploadToEndpoint(fileData, filename, "text/plain", selectedTags, finalText)
        }

        dialog.show()
    }

    // ==== SHARED IMAGE WORKFLOW ====
    private fun handleSharedImage(imageUri: Uri) {
        val config = ConfigManager.load(this)
        val hasEndpoint = config.endpoints.isNotEmpty()
        val hasKashFiles = config.kashFiles.isNotEmpty()

        when {
            !hasEndpoint && !hasKashFiles -> {
                Snackbar.make(binding.root, "No endpoint or Kash Files configured!", Snackbar.LENGTH_LONG).show()
            }
            else -> {
                // Check 100MB limit for Images too
                val fileSize = contentResolver.openFileDescriptor(imageUri, "r")?.statSize ?: 0
                if (fileSize > 100 * 1024 * 1024) { // 100MB
                    Snackbar.make(binding.root, "Image too large! Keep it under 100MB!", Snackbar.LENGTH_LONG).show()
                    return
                }
                showDestinationChoiceForImage(imageUri)
            }
        }
    }

    private fun showDestinationChoiceForImage(imageUri: Uri) {
        val dialogView = layoutInflater.inflate(R.layout.dialog_upload_destination, null)
        val radioGroup = dialogView.findViewById<RadioGroup>(R.id.destinationRadioGroup)

        val config = ConfigManager.load(this)
        val hasEndpoint = config.endpoints.isNotEmpty()
        val hasKashFiles = config.kashFiles.isNotEmpty()

        // Update labels for image context
        dialogView.findViewById<RadioButton>(R.id.radioEndpoint).text = "Endpoint Only (AI Captioning)"
        dialogView.findViewById<RadioButton>(R.id.radioKashFiles).text = "Kash Files Only (Link + Caption)"
        dialogView.findViewById<RadioButton>(R.id.radioBoth).text = "Both (Full image to endpoint + Link to Kash Files)"

        dialogView.findViewById<RadioButton>(R.id.radioEndpoint).isEnabled = hasEndpoint
        dialogView.findViewById<RadioButton>(R.id.radioKashFiles).isEnabled = hasKashFiles
        dialogView.findViewById<RadioButton>(R.id.radioBoth).isEnabled = hasEndpoint && hasKashFiles

        when {
            hasEndpoint && hasKashFiles -> radioGroup.check(R.id.radioBoth)
            hasEndpoint -> radioGroup.check(R.id.radioEndpoint)
            hasKashFiles -> radioGroup.check(R.id.radioKashFiles)
        }

        val dialog = AlertDialog.Builder(this)
            .setView(dialogView)
            .create()

        dialogView.findViewById<Button>(R.id.btnConfirmDestination).setOnClickListener {
            val destination = when (radioGroup.checkedRadioButtonId) {
                R.id.radioEndpoint -> "endpoint"
                R.id.radioKashFiles -> "kashfiles"
                R.id.radioBoth -> "both"
                else -> null
            }

            if (destination != null) {
                dialog.dismiss()

                // Read image data
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val inputStream = contentResolver.openInputStream(imageUri)
                        val imageBytes = inputStream?.readBytes() ?: throw Exception("Failed to read image")
                        inputStream.close()

                        withContext(Dispatchers.Main) {
                            showCaptionDialogForImage(imageBytes, destination)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            Snackbar.make(binding.root, "Failed to read image: ${e.message}", Snackbar.LENGTH_SHORT).show()
                        }
                    }
                }
            } else {
                Toast.makeText(this, "Please select a destination", Toast.LENGTH_SHORT).show()
            }
        }

        dialogView.findViewById<Button>(R.id.btnCancelDestination).setOnClickListener {
            dialog.dismiss()
        }

        dialog.show()
    }

    private fun showCaptionDialogForImage(imageBytes: ByteArray, destination: String) {
        val dialogView = layoutInflater.inflate(R.layout.dialog_share_content, null)
        val titleView = dialogView.findViewById<TextView>(R.id.dialogTitle)

        // AUTOCOMPLETE FOR IMAGES
        val captionInput = dialogView.findViewById<AutoCompleteTextView>(R.id.captionInput)

        val tagsDisplay = dialogView.findViewById<TextView>(R.id.selectedTagsDisplay)
        val btnSelectTags = dialogView.findViewById<Button>(R.id.btnSelectTags)
        val btnCancel = dialogView.findViewById<Button>(R.id.btnCancelShare)
        val btnConfirm = dialogView.findViewById<Button>(R.id.btnConfirmShare)

        titleView.text = "Share Image"

        // Dynamic Hints based on destination
        when (destination) {
            "both" -> {
                titleView.text = "Upload to Both (Context Prompt)"
                captionInput.hint = "Enter AI Context Prompt (Caption hidden for file)"
            }
            "endpoint" -> {
                titleView.text = "Endpoint Upload"
                captionInput.hint = "Enter AI Context Prompt"
            }
            "kashfiles" -> {
                titleView.text = "Kash Files Upload"
                captionInput.hint = "Enter File Caption"
            }
            else -> captionInput.hint = "Caption (optional)"
        }

        // SETUP PROMPTS
        val savedPrompts = savedPromptsManager.getPrompts()
        val adapter = ArrayAdapter(this, android.R.layout.simple_dropdown_item_1line, savedPrompts)
        captionInput.setAdapter(adapter)
        captionInput.threshold = 1

        var selectedTags = ""

        btnSelectTags.setOnClickListener {
            showTagSelectionDialog { tags ->
                selectedTags = tags
                tagsDisplay.text = if (tags.isBlank()) "Tags: (none)" else "Tags: $tags"
            }
        }

        val dialog = AlertDialog.Builder(this)
            .setView(dialogView)
            .create()

        btnCancel.setOnClickListener {
            dialog.dismiss()
        }

        btnConfirm.setOnClickListener {
            val caption = captionInput.text.toString().trim()

            // SAVE PROMPT
            savedPromptsManager.savePrompt(caption)

            dialog.dismiss()

            val filename = "image_${System.currentTimeMillis()}.jpg"

            when (destination) {
                "endpoint" -> uploadToEndpoint(imageBytes, filename, "image/jpeg", selectedTags, caption)
                "kashfiles" -> uploadImageToKashFilesOnly(imageBytes, filename, selectedTags, caption)
                "both" -> uploadImageToBoth(imageBytes, filename, selectedTags, caption)
            }
        }

        dialog.show()
    }

    // ==== SHARED RAW FILE WORKFLOW ====
    private fun handleSharedRawFile(fileUri: Uri, mimeType: String) {
        val config = ConfigManager.load(this)
        val hasEndpoint = config.endpoints.isNotEmpty()
        val hasKashFiles = config.kashFiles.isNotEmpty()

        // 1. Check if we have ANY place to send it
        if (!hasEndpoint && !hasKashFiles) {
            Snackbar.make(
                binding.root,
                "No Endpoint or Kash Files configured!",
                Snackbar.LENGTH_LONG
            ).show()
            return
        }

        // 2. Add the size check to save the crash (100MB limit)
        val fileSize = contentResolver.openFileDescriptor(fileUri, "r")?.statSize ?: 0
        if (fileSize > 100 * 1024 * 1024) { // 100MB
            Snackbar.make(binding.root, "File too large! Keep it under 100MB!", Snackbar.LENGTH_LONG).show()
            return
        }

        // 3. Proceed to Choice
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val inputStream = contentResolver.openInputStream(fileUri)
                val fileBytes = inputStream?.readBytes() ?: throw Exception("Failed to read file")
                inputStream.close()

                val filename = getFileNameFromUri(fileUri) ?: "file_${System.currentTimeMillis()}"

                withContext(Dispatchers.Main) {
                    showDestinationChoiceForRawFile(fileBytes, filename, mimeType)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    Snackbar.make(
                        binding.root,
                        "Failed to read file: ${e.message}",
                        Snackbar.LENGTH_SHORT
                    ).show()
                }
            }
        }
    }

    private fun showDestinationChoiceForRawFile(fileBytes: ByteArray, filename: String, mimeType: String) {
        val dialogView = layoutInflater.inflate(R.layout.dialog_upload_destination, null)
        val radioGroup = dialogView.findViewById<RadioGroup>(R.id.destinationRadioGroup)

        val config = ConfigManager.load(this)
        val hasEndpoint = config.endpoints.isNotEmpty()
        val hasKashFiles = config.kashFiles.isNotEmpty()

        // GIL: TRIPLE PLAY LABELS
        dialogView.findViewById<RadioButton>(R.id.radioEndpoint).text = "AI Ingest Only (Process PDF/Audio/Video)"
        dialogView.findViewById<RadioButton>(R.id.radioKashFiles).text = "Kash Files Only (Storage + Link Post)"
        dialogView.findViewById<RadioButton>(R.id.radioBoth).text = "The Works (Storage + Link Post + AI Ingest)"

        dialogView.findViewById<RadioButton>(R.id.radioEndpoint).isEnabled = hasEndpoint
        dialogView.findViewById<RadioButton>(R.id.radioKashFiles).isEnabled = hasKashFiles
        dialogView.findViewById<RadioButton>(R.id.radioBoth).isEnabled = hasEndpoint && hasKashFiles

        // Default selection
        when {
            hasEndpoint && hasKashFiles -> radioGroup.check(R.id.radioBoth)
            hasEndpoint -> radioGroup.check(R.id.radioEndpoint)
            hasKashFiles -> radioGroup.check(R.id.radioKashFiles)
        }

        val dialog = AlertDialog.Builder(this)
            .setView(dialogView)
            .create()

        dialogView.findViewById<Button>(R.id.btnConfirmDestination).setOnClickListener {
            val destination = when (radioGroup.checkedRadioButtonId) {
                R.id.radioEndpoint -> "endpoint"
                R.id.radioKashFiles -> "kashfiles"
                R.id.radioBoth -> "both"
                else -> null
            }

            if (destination != null) {
                dialog.dismiss()
                showCaptionDialogForRawFile(fileBytes, filename, mimeType, destination)
            } else {
                Toast.makeText(this, "Please select a destination", Toast.LENGTH_SHORT).show()
            }
        }

        dialogView.findViewById<Button>(R.id.btnCancelDestination).setOnClickListener {
            dialog.dismiss()
        }

        dialog.show()
    }

    private fun getFileNameFromUri(uri: Uri): String? {
        var result: String? = null
        if (uri.scheme == "content") {
            val cursor = contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) {
                        result = it.getString(nameIndex)
                    }
                }
            }
        }
        if (result == null) {
            result = uri.path
            val cut = result?.lastIndexOf('/')
            if (cut != -1 && cut != null) {
                result = result?.substring(cut + 1)
            }
        }
        return result
    }

    private fun showCaptionDialogForRawFile(
        fileBytes: ByteArray,
        filename: String,
        mimeType: String,
        destination: String
    ) {
        val dialogView = layoutInflater.inflate(R.layout.dialog_share_content, null)
        val titleView = dialogView.findViewById<TextView>(R.id.dialogTitle)
        val previewView = dialogView.findViewById<TextView>(R.id.sharedContentPreview)

        // AUTOCOMPLETE FOR FILES
        val captionInput = dialogView.findViewById<AutoCompleteTextView>(R.id.captionInput)

        val tagsDisplay = dialogView.findViewById<TextView>(R.id.selectedTagsDisplay)
        val btnSelectTags = dialogView.findViewById<Button>(R.id.btnSelectTags)
        val btnCancel = dialogView.findViewById<Button>(R.id.btnCancelShare)
        val btnConfirm = dialogView.findViewById<Button>(R.id.btnConfirmShare)

        // Dynamic Title & Hint
        when (destination) {
            "endpoint" -> {
                titleView.text = "Direct AI Ingest"
                captionInput.hint = "Context Prompt for AI"
            }
            "kashfiles" -> {
                titleView.text = "Upload to Kash Files"
                captionInput.hint = "File Caption"
            }
            "both" -> {
                titleView.text = "The Works (Storage + AI)"
                captionInput.hint = "Caption / Context Prompt"
            }
        }

        previewView.text = "File: $filename\nType: $mimeType"
        previewView.visibility = android.view.View.VISIBLE

        // SETUP PROMPTS
        val savedPrompts = savedPromptsManager.getPrompts()
        val adapter = ArrayAdapter(this, android.R.layout.simple_dropdown_item_1line, savedPrompts)
        captionInput.setAdapter(adapter)
        captionInput.threshold = 1

        var selectedTags = ""

        btnSelectTags.setOnClickListener {
            showTagSelectionDialog { tags ->
                selectedTags = tags
                tagsDisplay.text = if (tags.isBlank()) "Tags: (none)" else "Tags: $tags"
            }
        }

        val dialog = AlertDialog.Builder(this)
            .setView(dialogView)
            .create()

        btnCancel.setOnClickListener {
            dialog.dismiss()
        }

        btnConfirm.setOnClickListener {
            val caption = captionInput.text.toString().trim()

            // SAVE PROMPT
            savedPromptsManager.savePrompt(caption)

            dialog.dismiss()

            when (destination) {
                "endpoint" -> {
                    // DIRECT INGEST
                    uploadToEndpoint(fileBytes, filename, mimeType, selectedTags, caption)
                }
                "kashfiles" -> {
                    uploadRawFileToKashFilesOnly(fileBytes, filename, mimeType, selectedTags, caption)
                }
                "both" -> {
                    // TRIPLE PLAY / SECRET INJECTION
                    uploadRawFileToBoth(fileBytes, filename, mimeType, selectedTags, caption)
                }
            }
        }

        dialog.show()
    }

    // ==== TAG SELECTION ====
    private fun showTagSelectionDialog(callback: (String) -> Unit) {
        val config = ConfigManager.load(this)
        val recentTags = recentTagsManager.getRecentTagsList(config)

        val dialog = TagSelectionDialog(recentTags) { tags ->
            if (tags.isNotBlank()) {
                val newConfig = recentTagsManager.updateRecentTags(tags, config)
                ConfigManager.save(this, newConfig)
            }
            callback(tags)
        }
        dialog.show(supportFragmentManager, "tags")
    }

    // ==== UPLOAD METHODS ====
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
                val fromTag = "from-$ep.device"
                val effectiveTags = appendDeviceToTags(tags, ep.device,)
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

    private fun uploadToKashFilesOnly(
        fileData: ByteArray,
        filename: String,
        contentType: String,
        tags: String,
        caption: String
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            val config = ConfigManager.load(this@MainActivity)
            val kf = config.kashFiles.getOrNull(config.lastUsedKashFiles)

            if (kf == null) {
                Snackbar.make(binding.root, "No Kash Files selected!", Snackbar.LENGTH_SHORT).show()
                return@launch
            }

            val client = KashFilesClient(kf)
            val result = client.uploadFile(filename, fileData, contentType, tags, caption)

            if (result.ok && result.download != null) {
                val fullUrl = "${kf.url}${result.download}"
                Snackbar.make(
                    binding.root,
                    "✅ Uploaded to Kash Files!\nURL: $fullUrl",
                    Snackbar.LENGTH_LONG
                ).show()
            } else {
                Snackbar.make(binding.root, "❌ Upload failed: ${result.error}", Snackbar.LENGTH_SHORT).show()
            }
        }
    }

    private fun uploadLinkToBoth(
        fileData: ByteArray,
        filename: String,
        tags: String,
        fullText: String
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            val config = ConfigManager.load(this@MainActivity)
            val kf = config.kashFiles.getOrNull(config.lastUsedKashFiles)

            if (kf == null) {
                Snackbar.make(binding.root, "No Kash Files selected!", Snackbar.LENGTH_SHORT).show()
                return@launch
            }

            val client = KashFilesClient(kf)
            val result = client.uploadFile(filename, fileData, "text/plain", tags, fullText)

            if (result.ok && result.download != null) {
                val fullUrl = "${kf.url}${result.download}"
                val linkDigest = """
                Link saved to Kash Files
                URL: $fullUrl
                
                $fullText
                """.trimIndent()

                val linkFilename = "link_${System.currentTimeMillis()}.txt"
                uploadToEndpoint(linkDigest.toByteArray(), linkFilename, "text/plain", tags, linkDigest)

                Snackbar.make(
                    binding.root,
                    "✅ Uploaded to both!\n→ Kash Files\n→ Link digest to endpoint",
                    Snackbar.LENGTH_LONG
                ).show()
            } else {
                Snackbar.make(binding.root, "❌ Kash Files upload failed: ${result.error}", Snackbar.LENGTH_SHORT).show()
            }
        }
    }

    private fun uploadImageToKashFilesOnly(
        imageBytes: ByteArray,
        filename: String,
        tags: String,
        caption: String
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            val config = ConfigManager.load(this@MainActivity)
            val kf = config.kashFiles.getOrNull(config.lastUsedKashFiles)

            if (kf == null) {
                Snackbar.make(binding.root, "No Kash Files selected!", Snackbar.LENGTH_SHORT).show()
                return@launch
            }

            val client = KashFilesClient(kf)
            val result = client.uploadFile(filename, imageBytes, "image/jpeg", tags, caption)

            if (result.ok && result.download != null) {
                val fullUrl = "${kf.url}${result.download}"
                val filenameTag = filename.substringBeforeLast('.')
                val enhancedTags = if (tags.isBlank()) filenameTag else "$tags,$filenameTag"

                val config = ConfigManager.load(this@MainActivity)
                val hasEndpoint = config.endpoints.isNotEmpty()

                if (hasEndpoint) {
                    val linkText = """
                    Image: $filename
                    Link: $fullUrl
                    
                    ${if (caption.isNotBlank()) caption else "Image uploaded to Kash Files"}
                    """.trimIndent()

                    val linkFilename = "img_link_${System.currentTimeMillis()}.txt"
                    uploadToEndpoint(linkText.toByteArray(), linkFilename, "text/plain", enhancedTags, linkText)

                    Snackbar.make(
                        binding.root,
                        "✅ Image uploaded!\n→ Kash Files\n→ Link digest to endpoint",
                        Snackbar.LENGTH_LONG
                    ).show()
                } else {
                    Snackbar.make(
                        binding.root,
                        "✅ Image uploaded to Kash Files!\nURL: $fullUrl",
                        Snackbar.LENGTH_LONG
                    ).show()
                }
            } else {
                Snackbar.make(binding.root, "❌ Upload failed: ${result.error}", Snackbar.LENGTH_SHORT).show()
            }
        }
    }

    private fun uploadImageToBoth(
        imageBytes: ByteArray,
        filename: String,
        tags: String,
        caption: String
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            val config = ConfigManager.load(this@MainActivity)
            val kf = config.kashFiles.getOrNull(config.lastUsedKashFiles)

            if (kf == null) {
                Snackbar.make(binding.root, "No Kash Files selected!", Snackbar.LENGTH_SHORT).show()
                return@launch
            }

            val client = KashFilesClient(kf)
            val result = client.uploadFile(filename, imageBytes, "image/jpeg", tags, caption)

            if (result.ok && result.download != null) {
                val fullUrl = "${kf.url}${result.download}"
                val filenameTag = filename.substringBeforeLast('.')
                val enhancedTags = if (tags.isBlank()) filenameTag else "$tags,$filenameTag"

                // SECRET INJECTION LOGIC FOR IMAGES
                val injectedPrompt = "$caption and when you're done you must end your response with $fullUrl"

                uploadToEndpoint(imageBytes, filename, "image/jpeg", enhancedTags, injectedPrompt)

                Snackbar.make(
                    binding.root,
                    "✅ Image uploaded! Link injected into AI context.",
                    Snackbar.LENGTH_LONG
                ).show()
            } else {
                Snackbar.make(binding.root, "❌ Kash Files upload failed: ${result.error}", Snackbar.LENGTH_SHORT).show()
            }
        }
    }

    private fun uploadRawFileToKashFilesOnly(
        fileData: ByteArray,
        filename: String,
        mimeType: String,
        tags: String,
        caption: String
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            val config = ConfigManager.load(this@MainActivity)
            val kf = config.kashFiles.getOrNull(config.lastUsedKashFiles)

            if (kf == null) {
                Snackbar.make(binding.root, "No Kash Files selected!", Snackbar.LENGTH_SHORT).show()
                return@launch
            }

            val client = KashFilesClient(kf)
            val result = client.uploadFile(filename, fileData, mimeType, tags, caption)

            if (result.ok && result.download != null) {
                val fullUrl = "${kf.url}${result.download}"

                // --- FIX: Add Link Posting Logic ---
                val config = ConfigManager.load(this@MainActivity)
                val hasEndpoint = config.endpoints.isNotEmpty()
                // --- test f ---
                if (hasEndpoint) {
                    // 1. Create the "Link Digest" Text
                    val linkText = """
                    File: $filename
                    Type: $mimeType
                    Kash Files Link: $fullUrl
                    
                    ${if (caption.isNotBlank()) caption else "File available at link above."}
                    """.trimIndent()

                    // 2. Create a filename for this link text
                    val filenameTag = filename.substringBeforeLast('.')
                    val linkFilename = "${filenameTag}_link_${System.currentTimeMillis()}.txt"

                    // 3. Upload the Link Text to the Endpoint (AI/Indexer)
                    uploadToEndpoint(linkText.toByteArray(), linkFilename, "text/plain", tags, linkText)

                    Snackbar.make(
                        binding.root,
                        "✅ File uploaded to Kash Files!\nLink digest posted to App.",
                        Snackbar.LENGTH_LONG
                    ).show()
                } else {
                    // Fallback if no endpoint is configured
                    Snackbar.make(
                        binding.root,
                        "✅ File uploaded to Kash Files!\nURL: $fullUrl",
                        Snackbar.LENGTH_LONG
                    ).show()
                }
            } else {
                Snackbar.make(binding.root, "❌ Upload failed: ${result.error}", Snackbar.LENGTH_SHORT).show()
            }
        }
    }

    private fun uploadRawFileToBoth(
        fileBytes: ByteArray,
        filename: String,
        mimeType: String,
        tags: String,
        caption: String
    ) {
        CoroutineScope(Dispatchers.Main).launch {
            val config = ConfigManager.load(this@MainActivity)
            val kf = config.kashFiles.getOrNull(config.lastUsedKashFiles)

            if (kf == null) {
                Snackbar.make(binding.root, "No Kash Files selected!", Snackbar.LENGTH_SHORT).show()
                return@launch
            }

            val client = KashFilesClient(kf)
            val result = client.uploadFile(filename, fileBytes, mimeType, tags, caption)

            if (result.ok && result.download != null) {
                val fullUrl = "${kf.url}${result.download}"
                val filenameTag = filename.substringBeforeLast('.')
                val enhancedTags = if (tags.isBlank()) filenameTag else "$tags,$filenameTag"

                if (mimeType.startsWith("video/")) {
                    // === VIDEO LOGIC (Secret Injection) ===
                    val injectedPrompt = "$caption and when you're done you must end your response with $fullUrl"

                    uploadToEndpoint(fileBytes, filename, mimeType, enhancedTags, injectedPrompt)

                    Snackbar.make(
                        binding.root,
                        "✅ Video uploaded! Link injected into AI context.",
                        Snackbar.LENGTH_LONG
                    ).show()

                } else {
                    // === DOCS/OTHER LOGIC (Triple Play) ===
                    val linkDigest = """
                    File: $filename
                    Type: $mimeType
                    Kash Files Link: $fullUrl
                    
                    ${if (caption.isNotBlank()) caption else "File available at link above."}
                    """.trimIndent()

                    val linkFilename = "file_link_${filenameTag}_${Instant.now().epochSecond}.txt"

                    uploadToEndpoint(linkDigest.toByteArray(), linkFilename, "text/plain", enhancedTags, linkDigest)

                    delay(500)
                    uploadToEndpoint(fileBytes, filename, mimeType, enhancedTags, caption)

                    Snackbar.make(
                        binding.root,
                        "✅ The Works! Uploaded to Kash Files, Posted Link, AND sent File to AI!",
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
            val tagList = tags.split(',').map { it.trim() }.filter { it.isNotEmpty() }.toMutableList()

            // Create clean device name for tags
            val cleanDeviceName = normalizedDevice.lowercase().replace(" ", "-")

            // Add plain device name if not present
            if (!tagList.any { it.equals(cleanDeviceName, ignoreCase = true) }) {
                tagList.add(cleanDeviceName)
            }

            // Add from-device tag if not present
            val fromDeviceTag = "from-$cleanDeviceName"
            if (!tagList.any { it.equals(fromDeviceTag, ignoreCase = true) }) {
                tagList.add(fromDeviceTag)
            }

            return tagList.joinToString(",")
        }
        return tags
    }

    // ==== DEBUG METHODS ====
    private fun showSyncLogs() {
        val prefs = PodPreferences(this)
        val deviceNames = prefs.deviceNames

        lifecycleScope.launch {
            try {
                val database = PodDatabase.getDatabase(this@MainActivity)
                val repo = PodRepository(database.podDao())

                // Collect flows properly
                val activePods = repo.getActivePods().first()
                val allDigests = repo.getRecentDigests(100).first()

                val logMessage = buildString {
                    appendLine("=== SYNC DEBUG INFO ===")
                    appendLine()
                    appendLine("Device Names (${deviceNames.size}):")
                    if (deviceNames.isEmpty()) {
                        appendLine("  ⚠️ No device names configured!")
                    } else {
                        deviceNames.forEach { appendLine("  • $it") }
                    }
                    appendLine()
                    appendLine("Active Pods (${activePods.size}):")
                    if (activePods.isEmpty()) {
                        appendLine("  ⚠️ No active pods!")
                    } else {
                        activePods.forEach { pod ->
                            appendLine("  • ${pod.name}")
                            appendLine("    - Notify new: ${pod.notifyNewDigests}")
                            appendLine("    - Notify replies: ${pod.notifyReplies}")
                            appendLine("    - Last refresh: ${if (pod.lastRefresh > 0) "${(System.currentTimeMillis() - pod.lastRefresh) / 60000} min ago" else "never"}")
                        }
                    }
                    appendLine()
                    appendLine("Total Digests in DB: ${allDigests.size}")

                    if (allDigests.isEmpty()) {
                        appendLine("  ⚠️ No digests in database - sync may not be working")
                    } else {
                        appendLine()
                        appendLine("Recent Digests (last 5):")
                        allDigests.sortedByDescending { it.createdAt }.take(5).forEach { digest ->
                            appendLine("  • ID: ${digest.id.take(8)}...")
                            appendLine("    Created: ${digest.createdAt}")
                            appendLine("    Tags: ${digest.tags.joinToString(", ")}")
                            appendLine("    IsMyPost: ${digest.isMyPost}")
                            appendLine("    IsReplyToMe: ${digest.isReplyToMe}")
                            appendLine("    InPods: ${digest.inPods.joinToString(", ")}")
                        }
                    }

                    appendLine()
                    appendLine("Notification Tracking:")
                    val myPosts = repo.getMyPosts().first()
                    val repliesToMe = repo.getRepliesToMe().first()
                    appendLine("  My Posts: ${myPosts.size}")
                    appendLine("  Replies to Me: ${repliesToMe.size}")
                }

                withContext(Dispatchers.Main) {
                    AlertDialog.Builder(this@MainActivity)
                        .setTitle("Sync Debug Info")
                        .setMessage(logMessage)
                        .setPositiveButton("Copy to Clipboard") { _, _ ->
                            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                            val clip = android.content.ClipData.newPlainText("Sync Debug", logMessage)
                            clipboard.setPrimaryClip(clip)
                            Toast.makeText(this@MainActivity, "Copied to clipboard", Toast.LENGTH_SHORT).show()
                        }
                        .setNegativeButton("Close", null)
                        .show()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    AlertDialog.Builder(this@MainActivity)
                        .setTitle("Error")
                        .setMessage("Failed to load debug info:\n${e.message}")
                        .setPositiveButton("OK", null)
                        .show()
                }
            }
        }
    }

    private fun showDebugOptionsDialog() {
        val options = arrayOf(
            "View Sync Logs",
            "Test Notification",
            "Force Sync Now",
            "WorkManager Status"
        )

        AlertDialog.Builder(this)
            .setTitle("Debug Options")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> showSyncLogs()
                    1 -> sendTestNotification()
                    2 -> forceSyncNow()
                    3 -> showWorkManagerStatus()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun sendTestNotification() {
        val testDigest = Digest(
            id = "test-${System.currentTimeMillis()}",
            title = "Test Notification",
            content = "This is a test notification from Kash Stash. If you see this, notifications are working!",
            tags = listOf("test"),
            sourceNode = "test",
            createdAt = Date(),
            inPods = listOf("Test Pod")
        )

        val testPod = PodConfig(
            name = "Test Pod",
            entranceNodeUrl = "test",
            presharedKey = "test",
            notifyNewDigests = true,
            notifyReplies = true
        )

        val notificationManager = NotificationManager(this)
        notificationManager.checkForNewContent(listOf(testDigest), testPod, setOf("test"))

        Toast.makeText(this, "Test notification sent - check your notifications", Toast.LENGTH_LONG).show()
    }

    private fun forceSyncNow() {
        lifecycleScope.launch {
            try {
                Toast.makeText(this@MainActivity, "Starting sync...", Toast.LENGTH_SHORT).show()

                val database = PodDatabase.getDatabase(this@MainActivity)
                val repo = PodRepository(database.podDao())
                val prefs = PodPreferences(this@MainActivity)
                val podClient = PodClient()

                val deviceNames = prefs.deviceNames
                val activePods = repo.getActivePods().first()

                if (deviceNames.isEmpty()) {
                    Toast.makeText(this@MainActivity, "No device names configured", Toast.LENGTH_LONG).show()
                    return@launch
                }

                if (activePods.isEmpty()) {
                    Toast.makeText(this@MainActivity, "No active pods", Toast.LENGTH_LONG).show()
                    return@launch
                }

                val aggregator = MultiPodAggregator(
                    podClient, repo, deviceNames
                )

                val digests = withContext(Dispatchers.IO) {
                    aggregator.fetchFromAllPods(activePods)
                }

                repo.insertDigests(digests)

                prefs.lastSyncTime = System.currentTimeMillis()

                Toast.makeText(
                    this@MainActivity,
                    "Sync complete! Fetched ${digests.size} digests",
                    Toast.LENGTH_LONG
                ).show()

            } catch (e: Exception) {
                Toast.makeText(
                    this@MainActivity,
                    "Sync failed: ${e.message}",
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }

    private fun showWorkManagerStatus() {
        lifecycleScope.launch {
            try {
                val workManager = WorkManager.getInstance(this@MainActivity)

                val periodicWork = withContext(Dispatchers.IO) {
                    workManager.getWorkInfosForUniqueWork("pod_sync_work").get()
                }
                val immediateWork = withContext(Dispatchers.IO) {
                    workManager.getWorkInfosForUniqueWork("pod_sync_immediate").get()
                }

                val status = buildString {
                    appendLine("=== WORKMANAGER STATUS ===")
                    appendLine()
                    appendLine("Periodic Work:")
                    if (periodicWork.isEmpty()) {
                        appendLine("  ⚠️ No periodic work scheduled!")
                        appendLine("  This means background sync is not running.")
                    } else {
                        periodicWork.forEach { info ->
                            appendLine("  State: ${info.state}")
                            appendLine("  Tags: ${info.tags.joinToString()}")
                            appendLine("  Run Attempt: ${info.runAttemptCount}")
                            if (info.state == WorkInfo.State.FAILED) {
                                appendLine("  ⚠️ FAILED - Check logs")
                            }
                        }
                    }
                    appendLine()
                    appendLine("Immediate Work:")
                    if (immediateWork.isEmpty()) {
                        appendLine("  No immediate work")
                    } else {
                        immediateWork.forEach { info ->
                            appendLine("  State: ${info.state}")
                            appendLine("  Run Attempt: ${info.runAttemptCount}")
                        }
                    }
                }

                withContext(Dispatchers.Main) {
                    AlertDialog.Builder(this@MainActivity)
                        .setTitle("WorkManager Status")
                        .setMessage(status)
                        .setPositiveButton("Reschedule Sync") { _, _ ->
                            rescheduleBackgroundSync()
                        }
                        .setNegativeButton("Close", null)
                        .show()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    Toast.makeText(
                        this@MainActivity,
                        "Error: ${e.message}",
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }
    }

    private fun rescheduleBackgroundSync() {
        try {
            // Cancel existing work
            WorkManager.getInstance(this).cancelUniqueWork("pod_sync_work")

            // Wait a moment then reschedule
            lifecycleScope.launch {
                delay(500)
                BackgroundSyncManager.syncDeviceNamesFromEndpoints(this@MainActivity)
                BackgroundSyncManager.setBackgroundSyncEnabled(this@MainActivity, true)
                Toast.makeText(this@MainActivity, "Background sync rescheduled", Toast.LENGTH_SHORT).show()
            }
        } catch (e: Exception) {
            Toast.makeText(this, "Failed to reschedule: ${e.message}", Toast.LENGTH_LONG).show()
        }
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
            R.id.action_notification_status -> {
                showNotificationStatus()
                true
            }
            R.id.action_settings -> true
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun showNotificationStatus() {
        val status = BackgroundSyncManager.isProperlyConfigured(this)
        val prefs = PodPreferences(this)

        val message = buildString {
            appendLine("Status: ${if (status.isFullyConfigured) "✓ Active" else "⚠ Incomplete"}")
            appendLine()
            appendLine("Device Names:")
            if (status.deviceNames.isEmpty()) {
                appendLine("  None configured - add an endpoint")
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

            if (status.lastSyncError != null) {
                appendLine()
                appendLine("⚠️ Last Error:")
                appendLine(status.lastSyncError)
            }
        }

        val builder = AlertDialog.Builder(this)
            .setTitle("Background Notifications")
            .setMessage(message)
            .setPositiveButton("Test Sync Now") { _, _ ->
                BackgroundSyncManager.triggerImmediateSync(this)
                Toast.makeText(this, "Sync triggered - check status again in a few seconds", Toast.LENGTH_LONG).show()
            }
            .setNegativeButton("Close", null)

        builder.setNeutralButton("Debug") { _, _ ->
            showDebugOptionsDialog()
        }

        builder.show()
    }
}