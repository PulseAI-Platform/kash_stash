package com.pulseai.kashstash

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

class SavedPromptsManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("kash_stash_prompts", Context.MODE_PRIVATE)
    private val gson = Gson()
    private val MAX_PROMPTS = 50

    fun savePrompt(prompt: String) {
        if (prompt.isBlank()) return

        val list = getPrompts().toMutableList()
        // Remove if exists to move to top
        list.remove(prompt)
        list.add(0, prompt)

        if (list.size > MAX_PROMPTS) {
            list.removeAt(list.size - 1)
        }

        prefs.edit().putString("saved_prompts_json", gson.toJson(list)).apply()
    }

    fun getPrompts(): List<String> {
        val json = prefs.getString("saved_prompts_json", null) ?: return emptyList()
        val type = object : TypeToken<List<String>>() {}.type
        return gson.fromJson(json, type)
    }
}