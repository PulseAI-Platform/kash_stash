package com.pulseai.kashstash

import android.content.Context
import com.google.gson.Gson
import com.google.gson.JsonParser

object ConfigManager {
    private const val PREFS_NAME = "kashstash_prefs"
    private const val CONFIG_KEY = "config_json"
    private val gson = Gson()

    fun load(context: Context): KashStashConfig {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(CONFIG_KEY, null)

        return if (json != null) {
            try {
                // Parse and migrate if needed
                val config = gson.fromJson(json, KashStashConfig::class.java)
                migrateConfig(config)
            } catch (e: Exception) {
                // If parsing fails, check if it's old format
                migrateFromOldFormat(json) ?: KashStashConfig()
            }
        } else {
            KashStashConfig()
        }
    }

    private fun migrateConfig(config: KashStashConfig): KashStashConfig {
        // Ensure all endpoints have new fields with defaults
        val migratedEndpoints = config.endpoints.map { endpoint ->
            if (endpoint.configDigestId.isEmpty() &&
                endpoint.configDigestTags == "agent-config" &&
                endpoint.configCacheMinutes == 5) {
                // Already has defaults, no migration needed
                endpoint
            } else {
                endpoint
            }
        }

        return config.copy(
            endpoints = migratedEndpoints,
            kashFiles = config.kashFiles ?: emptyList(),
            recentTags = config.recentTags ?: emptyList()
        )
    }

    private fun migrateFromOldFormat(json: String): KashStashConfig? {
        return try {
            // Try to parse old format with just endpoints and lastUsedEndpoint
            val jsonObject = JsonParser.parseString(json).asJsonObject
            val endpoints = gson.fromJson(jsonObject.get("endpoints"), Array<EndpointConfig>::class.java)?.toList() ?: emptyList()
            val lastUsedEndpoint = jsonObject.get("lastUsedEndpoint")?.asInt ?: 0

            KashStashConfig(
                endpoints = endpoints,
                lastUsedEndpoint = lastUsedEndpoint,
                kashFiles = emptyList(),
                lastUsedKashFiles = 0,
                recentTags = emptyList()
            )
        } catch (e: Exception) {
            null
        }
    }

    fun save(context: Context, config: KashStashConfig) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(CONFIG_KEY, gson.toJson(config)).apply()
    }
}