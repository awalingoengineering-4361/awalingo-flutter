package com.example.awalingo.push

import android.content.Context
import org.json.JSONObject

interface PushStorage { fun read(key: String): String?; fun write(key: String, value: String?) }
class PushStore(private val storage: PushStorage) {
    constructor(context: Context) : this(object : PushStorage {
        private val preferences = context.getSharedPreferences("awalingo_push", Context.MODE_PRIVATE)
        override fun read(key: String) = preferences.getString(key, null)
        override fun write(key: String, value: String?) { preferences.edit().putString(key, value).commit() }
    })
    var token: String?
        get() = storage.read("token")
        set(value) = storage.write("token", value)
    fun gate(): PushGate {
        val parts = storage.read("gate")?.split('\n') ?: return PushGate(null, "", false)
        return if (parts.size == 3) PushGate(parts[0].ifEmpty { null }, parts[1], parts[2] == "true") else PushGate(null, "", false)
    }
    fun setGate(gate: PushGate) {
        val previous = gate()
        if (previous.ownerId != gate.ownerId || previous.environment != gate.environment || !gate.enabled) storage.write("tap", null)
        storage.write("gate", "${gate.ownerId ?: ""}\n${gate.environment}\n${gate.enabled}")
    }
    fun saveTap(payload: Map<String, String>) = storage.write("tap", JSONObject(payload).toString())
    fun takeTap(): Map<String, String>? {
        val json = storage.read("tap") ?: return null
        storage.write("tap", null)
        return try { val obj = JSONObject(json); obj.keys().asSequence().associateWith { obj.getString(it) } } catch (_: Exception) { null }
    }
    companion object { val lock = Any() }
}
