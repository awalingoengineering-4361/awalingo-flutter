package com.example.awalingo.push

import org.junit.Assert.*
import org.junit.Test

class PushPolicyTest {
    private val gate = PushGate("A", "test.supabase.co", true)
    private val payload = mapOf("v" to "1", "recipientId" to "A", "environment" to "test.supabase.co", "messageId" to "message-1", "title" to "Hello", "body" to "World", "link" to "/profile")
    @Test fun acceptsOnlyCompleteMatchingEnabledPayloads() {
        assertTrue(PushPolicy.accepts(payload, gate))
        assertFalse(PushPolicy.accepts(payload, gate.copy(enabled = false)))
        assertFalse(PushPolicy.accepts(payload, gate.copy(ownerId = "B")))
        assertFalse(PushPolicy.accepts(payload, gate.copy(environment = "other.supabase.co")))
        for (key in payload.keys) assertFalse("missing $key", PushPolicy.accepts(payload - key, gate))
        for ((key, value) in listOf("v" to "2", "link" to "https://evil.test", "link" to "//evil.test", "link" to "/\\evil.test", "messageId" to "", "body" to "x".repeat(601))) {
            assertFalse("invalid $key", PushPolicy.accepts(payload + (key to value), gate))
        }
    }
    @Test fun notificationIdentityIsStableAndDistinct() {
        assertEquals(PushPolicy.notificationTag(payload), PushPolicy.notificationTag(payload.toMap()))
        assertNotEquals(PushPolicy.notificationTag(payload), PushPolicy.notificationTag(payload + ("messageId" to "message-2")))
    }
    @Test fun tokenRotationAndClearedGateSurviveStoreRecreation() {
        val values = mutableMapOf<String, String>()
        val storage = object : PushStorage {
            override fun read(key: String) = values[key]
            override fun write(key: String, value: String?) { if (value == null) values.remove(key) else values[key] = value }
        }
        val store = PushStore(storage)
        store.token = "old"; store.token = "new"; store.setGate(gate)
        assertEquals("new", PushStore(storage).token)
        assertEquals(gate, PushStore(storage).gate())
        store.setGate(PushGate(null, "", false))
        assertFalse(PushStore(storage).gate().enabled)
        assertNull(PushStore(storage).gate().ownerId)
    }
}
