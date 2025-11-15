package com.pulseai.kashstash

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import com.google.zxing.*
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.common.GlobalHistogramBinarizer
import com.google.zxing.qrcode.QRCodeReader
import com.pulseai.kashstash.pods.models.PodConfig
import com.pulseai.kashstash.pods.storage.PodDatabase
import com.pulseai.kashstash.pods.storage.PodRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream
import kotlin.math.max

object QRConfigImporter {

    enum class ConfigType {
        KASH_FILES,
        MOBILE_ENDPOINT,
        DESKTOP_ENDPOINT,
        POD_CONFIG,
        UNKNOWN
    }

    /**
     * Decode QR code from an image URI with multiple attempts
     */
    fun decodeQRFromImage(imageUri: Uri, context: Context): Map<String, Any>? {
        return try {
            val inputStream: InputStream? = context.contentResolver.openInputStream(imageUri)
            var bitmap = BitmapFactory.decodeStream(inputStream)
            inputStream?.close()

            if (bitmap == null) {
                return null
            }

            // Try multiple approaches for better screen capture handling

            // Attempt 1: Original image
            var result = tryDecodeQR(bitmap)
            if (result != null) return parseQRJson(result)

            // Attempt 2: Scale down if image is too large (common with screenshots)
            if (bitmap.width > 1000 || bitmap.height > 1000) {
                val scaledBitmap = scaleBitmap(bitmap, 1000)
                result = tryDecodeQR(scaledBitmap)
                if (result != null) return parseQRJson(result)
            }

            // Attempt 3: Enhance contrast for screen captures
            val enhancedBitmap = enhanceContrast(bitmap)
            result = tryDecodeQR(enhancedBitmap)
            if (result != null) return parseQRJson(result)

            // Attempt 4: Try with inverted colors (for dark mode QRs)
            val invertedBitmap = invertColors(bitmap)
            result = tryDecodeQR(invertedBitmap)
            if (result != null) return parseQRJson(result)

            // Attempt 5: Crop center (in case of screenshots with borders)
            val croppedBitmap = cropCenter(bitmap)
            result = tryDecodeQR(croppedBitmap)
            if (result != null) return parseQRJson(result)

            // Attempt 6: Enhance contrast on cropped image
            val croppedEnhanced = enhanceContrast(croppedBitmap)
            result = tryDecodeQR(croppedEnhanced)
            if (result != null) return parseQRJson(result)

            null

        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    /**
     * Try to decode QR with multiple reader configurations
     */
    private fun tryDecodeQR(bitmap: Bitmap): String? {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        val source = RGBLuminanceSource(width, height, pixels)

        // Try with different binarizers
        val binarizers = listOf(
            HybridBinarizer(source),
            GlobalHistogramBinarizer(source)
        )

        for (binarizer in binarizers) {
            val binaryBitmap = BinaryBitmap(binarizer)

            // Try with QRCodeReader first (optimized for QR codes)
            try {
                val reader = QRCodeReader()
                val hints = mutableMapOf<DecodeHintType, Any>()
                hints[DecodeHintType.TRY_HARDER] = true
                hints[DecodeHintType.CHARACTER_SET] = "UTF-8"
                hints[DecodeHintType.PURE_BARCODE] = false

                val result = reader.decode(binaryBitmap, hints)
                if (result != null) {
                    return result.text
                }
            } catch (e: Exception) {
                // Continue to next attempt
            }

            // Try with MultiFormatReader
            try {
                val reader = MultiFormatReader()
                val hints = mutableMapOf<DecodeHintType, Any>()
                hints[DecodeHintType.POSSIBLE_FORMATS] = listOf(BarcodeFormat.QR_CODE)
                hints[DecodeHintType.TRY_HARDER] = true
                hints[DecodeHintType.CHARACTER_SET] = "UTF-8"

                val result = reader.decode(binaryBitmap, hints)
                if (result != null) {
                    return result.text
                }
            } catch (e: Exception) {
                // Continue to next attempt
            }
        }

        return null
    }

    /**
     * Scale bitmap to max dimension
     */
    private fun scaleBitmap(bitmap: Bitmap, maxDimension: Int): Bitmap {
        val width = bitmap.width
        val height = bitmap.height

        if (width <= maxDimension && height <= maxDimension) {
            return bitmap
        }

        val scale = maxDimension.toFloat() / max(width, height)
        val newWidth = (width * scale).toInt()
        val newHeight = (height * scale).toInt()

        return Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
    }

    /**
     * Enhance contrast for better QR detection on screens
     */
    private fun enhanceContrast(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val enhanced = Bitmap.createBitmap(width, height, bitmap.config ?: Bitmap.Config.ARGB_8888)

        for (x in 0 until width) {
            for (y in 0 until height) {
                val pixel = bitmap.getPixel(x, y)
                val r = Color.red(pixel)
                val g = Color.green(pixel)
                val b = Color.blue(pixel)

                // Calculate luminance
                val lum = (0.299 * r + 0.587 * g + 0.114 * b).toInt()

                // Apply threshold for better contrast (adjusted for screen captures)
                val newColor = if (lum > 140) Color.WHITE else Color.BLACK
                enhanced.setPixel(x, y, newColor)
            }
        }

        return enhanced
    }

    /**
     * Invert bitmap colors (for dark mode QR codes)
     */
    private fun invertColors(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val inverted = Bitmap.createBitmap(width, height, bitmap.config ?: Bitmap.Config.ARGB_8888)

        for (x in 0 until width) {
            for (y in 0 until height) {
                val pixel = bitmap.getPixel(x, y)
                val r = 255 - Color.red(pixel)
                val g = 255 - Color.green(pixel)
                val b = 255 - Color.blue(pixel)
                inverted.setPixel(x, y, Color.rgb(r, g, b))
            }
        }

        return inverted
    }

    /**
     * Crop center of image (removes screenshot borders)
     */
    private fun cropCenter(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height

        // Crop 10% from each edge
        val cropMargin = 0.1
        val newWidth = (width * (1 - 2 * cropMargin)).toInt()
        val newHeight = (height * (1 - 2 * cropMargin)).toInt()
        val startX = (width * cropMargin).toInt()
        val startY = (height * cropMargin).toInt()

        // Ensure we don't go out of bounds
        val safeWidth = if (startX + newWidth > width) width - startX else newWidth
        val safeHeight = if (startY + newHeight > height) height - startY else newHeight

        return if (startX >= 0 && startY >= 0 && safeWidth > 0 && safeHeight > 0) {
            Bitmap.createBitmap(bitmap, startX, startY, safeWidth, safeHeight)
        } else {
            bitmap // Return original if cropping would fail
        }
    }

    /**
     * Parse JSON string into a Map
     */
    private fun parseQRJson(jsonString: String): Map<String, Any>? {
        return try {
            val json = JSONObject(jsonString)
            val map = mutableMapOf<String, Any>()

            // Convert JSONObject to Map
            json.keys().forEach { key ->
                val value = json.get(key)
                map[key] = when (value) {
                    is JSONObject -> parseJsonObject(value)
                    is JSONArray -> parseJsonArray(value)
                    else -> value
                }
            }

            map
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    /**
     * Recursively parse nested JSONObjects
     */
    private fun parseJsonObject(json: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        json.keys().forEach { key ->
            val value = json.get(key)
            map[key] = when (value) {
                is JSONObject -> parseJsonObject(value)
                is JSONArray -> parseJsonArray(value)
                else -> value
            }
        }
        return map
    }

    /**
     * Parse JSONArray to List
     */
    private fun parseJsonArray(jsonArray: JSONArray): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until jsonArray.length()) {
            val value = jsonArray.get(i)
            list.add(when (value) {
                is JSONObject -> parseJsonObject(value)
                is JSONArray -> parseJsonArray(value)
                else -> value
            })
        }
        return list
    }

    /**
     * Detect what type of configuration this is
     */
    fun detectConfigType(config: Map<String, Any>): ConfigType {
        return when {
            // Check for Pod config - MUST be first!
            config.containsKey("entrance_url") &&
                    config.containsKey("preshared_key") -> ConfigType.POD_CONFIG

            // Check for Kash Files config
            config["type"] == "kashFiles" -> ConfigType.KASH_FILES

            // Check for mobile endpoint config (camelCase fields)
            config.containsKey("probeKey") &&
                    config.containsKey("nodeName") -> ConfigType.MOBILE_ENDPOINT

            // Check for desktop endpoint config (UPPER_CASE fields)
            config.containsKey("PROBE_KEY") &&
                    config.containsKey("NODE_NAME") -> ConfigType.DESKTOP_ENDPOINT

            else -> ConfigType.UNKNOWN
        }
    }

    /**
     * Extract Pod configuration - FIXED VERSION
     */
    fun extractPodConfig(config: Map<String, Any>): PodConfig? {
        return try {
            val name = config["name"] as? String ?: "Imported Pod"
            val entranceUrl = config["entrance_url"] as? String
            val presharedKey = config["preshared_key"] as? String

            // Return null if required fields are missing
            if (entranceUrl == null || presharedKey == null) {
                return null
            }

            // Fix: Handle tags very defensively
            val tagsList = try {
                when (val tagsRaw = config["tags"]) {
                    is List<*> -> {
                        // Filter and convert to String safely
                        tagsRaw.filterIsInstance<String>()
                    }
                    is ArrayList<*> -> {
                        // Handle ArrayList specifically
                        tagsRaw.filterIsInstance<String>()
                    }
                    else -> emptyList()
                }
            } catch (e: Exception) {
                // If anything goes wrong with tags, just use empty list
                emptyList<String>()
            }

            PodConfig(
                name = name,
                entranceNodeUrl = entranceUrl,
                presharedKey = presharedKey,
                cachedTags = tagsList,
                isActive = true
            )
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    /**
     * Import Pod config to database
     */
    fun importPodConfig(context: Context, podConfig: PodConfig) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val database = PodDatabase.getDatabase(context)
                val repository = PodRepository(database.podDao())
                repository.insertPod(podConfig)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    /**
     * Validate Pod config has required fields
     */
    fun validatePodConfig(podConfig: PodConfig): Boolean {
        return podConfig.name.isNotBlank() &&
                podConfig.entranceNodeUrl.isNotBlank() &&
                podConfig.presharedKey.isNotBlank()
    }

    /**
     * Convert mobile format config to desktop format
     * Mobile uses camelCase, desktop uses specific field names
     */
    fun convertMobileToDesktop(config: Map<String, Any>): EndpointConfig {
        return EndpointConfig(
            name = config["name"] as? String ?: "Imported from Mobile",
            device = config["device"] as? String ?: "mobile",
            probeKey = config["probeKey"] as? String ?: "",
            nodeName = config["nodeName"] as? String ?: "",
            probeId = config["probeId"] as? String ?: "29",
            configDigestId = config["configDigestId"] as? String ?: "",
            configDigestTags = config["configDigestTags"] as? String ?: "agent-config",
            configCacheMinutes = (config["configCacheMinutes"] as? Number)?.toInt() ?: 5
        )
    }

    /**
     * Convert desktop format config to EndpointConfig
     */
    fun convertDesktopConfig(config: Map<String, Any>): EndpointConfig {
        return EndpointConfig(
            name = config["name"] as? String ?: "Imported Endpoint",
            device = config["DEVICE"] as? String ?: "",
            probeKey = config["PROBE_KEY"] as? String ?: "",
            nodeName = config["NODE_NAME"] as? String ?: "",
            probeId = config["PROBE_ID"] as? String ?: "29",
            configDigestId = config["CONFIG_DIGEST_ID"] as? String ?: "",
            configDigestTags = config["CONFIG_DIGEST_TAGS"] as? String ?: "agent-config",
            configCacheMinutes = (config["CONFIG_CACHE_MINUTES"] as? Number)?.toInt() ?: 5
        )
    }

    /**
     * Extract Kash Files configuration
     */
    fun extractKashFilesConfig(config: Map<String, Any>): KashFilesConfig? {
        return try {
            KashFilesConfig(
                name = config["name"] as? String ?: "Imported Kash Files",
                url = config["url"] as? String ?: "",
                key = config["key"] as? String ?: ""
            )
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Validate endpoint config has required fields
     */
    fun validateEndpointConfig(endpoint: EndpointConfig): Boolean {
        return endpoint.name.isNotBlank() &&
                endpoint.probeKey.isNotBlank() &&
                endpoint.nodeName.isNotBlank() &&
                endpoint.probeId.isNotBlank()
    }

    /**
     * Validate Kash Files config has required fields
     */
    fun validateKashFilesConfig(kashFiles: KashFilesConfig): Boolean {
        return kashFiles.name.isNotBlank() &&
                kashFiles.url.isNotBlank() &&
                kashFiles.key.isNotBlank()
    }
}

/**
 * Custom luminance source for ZXing
 */
class RGBLuminanceSource(
    width: Int,
    height: Int,
    private val pixels: IntArray
) : LuminanceSource(width, height) {

    override fun getRow(y: Int, row: ByteArray?): ByteArray {
        val newRow = row ?: ByteArray(width)
        for (x in 0 until width) {
            val pixel = pixels[y * width + x]
            val r = (pixel shr 16) and 0xff
            val g = (pixel shr 8) and 0xff
            val b = pixel and 0xff
            // Calculate luminance
            newRow[x] = ((r + g * 2 + b) / 4).toByte()
        }
        return newRow
    }

    override fun getMatrix(): ByteArray {
        val matrix = ByteArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = pixels[y * width + x]
                val r = (pixel shr 16) and 0xff
                val g = (pixel shr 8) and 0xff
                val b = pixel and 0xff
                matrix[y * width + x] = ((r + g * 2 + b) / 4).toByte()
            }
        }
        return matrix
    }
}