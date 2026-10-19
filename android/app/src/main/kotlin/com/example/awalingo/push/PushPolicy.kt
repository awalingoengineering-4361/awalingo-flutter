package com.example.awalingo.push

import java.net.URI

data class PushGate(val ownerId: String?, val environment: String, val enabled: Boolean)
object PushPolicy {
    fun accepts(payload: Map<String, String>, gate: PushGate): Boolean {
        if (!gate.enabled || gate.ownerId.isNullOrEmpty() || gate.environment.isEmpty()) return false
        if (payload["v"] != "1" || payload["recipientId"] != gate.ownerId || payload["environment"] != gate.environment) return false
        val limits = mapOf("messageId" to 128, "title" to 120, "body" to 600, "link" to 1024)
        if (limits.any { (key, limit) -> payload[key].isNullOrBlank() || payload[key]!!.length > limit }) return false
        return relativeLink(payload["link"]!!)
    }
    fun relativeLink(link: String): Boolean {
        if (!link.startsWith("/") || link.startsWith("//") || link.any { it.isWhitespace() || it == '\\' || it.code < 32 }) return false
        return try { val uri = URI(link); !uri.isAbsolute && uri.rawAuthority == null && uri.rawFragment == null } catch (_: Exception) { false }
    }
    // Android tags are strings, so distinct provider IDs do not collide through hashCode().
    fun notificationTag(payload: Map<String, String>) = "awalingo:${payload["environment"]}:${payload["recipientId"]}:${payload["messageId"]}"
}
