package com.pulseai.kashstash

import android.content.Context
import com.google.gson.Gson

object ConfigManager {
    private const val PREFS_NAME = "kashstash_prefs"
    private const val CONFIG_KEY = "config_json"
    private val gson = Gson()

    fun load(context: Context): KashStashConfig {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(CONFIG_KEY, null)
        return if (json != null) gson.fromJson(json, KashStashConfig::class.java)
        else KashStashConfig()
    }

    fun save(context: Context, config: KashStashConfig) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(CONFIG_KEY, gson.toJson(config)).apply()
    }
}