package com.example.awalingo.push

import android.app.NotificationManager
import android.content.Context
import android.os.SystemClock
import java.io.FileInputStream
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class AndroidPushDeviceTest {
    private fun waitForCount(manager: NotificationManager, expected: Int) {
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (manager.activeNotifications.size != expected && SystemClock.elapsedRealtime() < deadline) SystemClock.sleep(20)
        assertEquals(expected, manager.activeNotifications.size)
    }
    @Test fun trayReplacesDuplicatesAndSuppressesOldOwnerWithoutFlutter() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val notifications = PushNotifications(context)
        val store = PushStore(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        InstrumentationRegistry.getInstrumentation().uiAutomation.grantRuntimePermission(context.packageName, "android.permission.POST_NOTIFICATIONS")
        val gate = PushGate("fixture-A", "fixture.supabase.co", true)
        val payload = mapOf("v" to "1", "recipientId" to "fixture-A", "environment" to "fixture.supabase.co", "messageId" to "fixture-message", "title" to "Awalingo test update", "body" to "Your contribution has an update", "link" to "/profile")
        try {
            notifications.cancelAll(); store.setGate(gate)
            assertTrue(notifications.post(payload)); assertTrue(notifications.post(payload))
            waitForCount(manager, 1)
            assertTrue(manager.activeNotifications[0].notification.contentIntent.isImmutable)
            store.setGate(gate.copy(ownerId = "fixture-B"))
            assertFalse(notifications.post(payload))
            store.setGate(gate.copy(enabled = false)); assertFalse(notifications.post(payload))
            notifications.cancelAll(); waitForCount(manager, 0)
            store.setGate(gate); assertTrue(notifications.post(payload))
            waitForCount(manager, 1)
            val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
            automation.executeShellCommand("cmd statusbar expand-notifications").close()
            SystemClock.sleep(500)
            // Gradle removes tested app data after instrumentation. Save fixture evidence
            // as shell-owned output so it survives that cleanup.
            automation.executeShellCommand("screencap -p /data/local/tmp/awalingo-push-tray.png").use { descriptor ->
                FileInputStream(descriptor.fileDescriptor).use { it.readBytes() }
            }
            automation.executeShellCommand("cmd statusbar collapse").close()
            // Exercise the real explicit PendingIntent/MainActivity boundary. No authenticated
            // Flutter fixture exists here, so the app must still require sign-in.
            manager.activeNotifications[0].notification.contentIntent.send()
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        } finally { store.setGate(PushGate(null, "", false)); notifications.cancelAll() }
    }
    @Test fun privateStoreConsumesTapsOnceAndClearsThemAcrossAccounts() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = PushStore(context)
        val payload = mapOf("messageId" to "one")
        store.setGate(PushGate("A", "test", true)); store.saveTap(payload)
        assertEquals(payload, PushStore(context).takeTap()); assertNull(store.takeTap())
        store.saveTap(payload); store.setGate(PushGate("B", "test", true)); assertNull(store.takeTap())
        store.setGate(PushGate(null, "", false))
    }
}
