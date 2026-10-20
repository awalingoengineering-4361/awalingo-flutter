package com.example.awalingo.push

import android.app.NotificationManager
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.filters.SdkSuppress
import android.content.Context
import android.os.SystemClock
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.File
import android.graphics.Bitmap
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

@SdkSuppress(minSdkVersion = 33)
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
            automation.serviceInfo = automation.serviceInfo.apply { flags = flags or AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS }
            automation.executeShellCommand("cmd statusbar expand-notifications").use { descriptor -> FileInputStream(descriptor.fileDescriptor).use { it.readBytes() } }
            SystemClock.sleep(500)
            fun findInTree(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
                if (node == null) return null
                if (node.text?.toString()?.contains("Awalingo test update") == true || node.contentDescription?.toString()?.contains("Awalingo test update") == true) return node
                for (index in 0 until node.childCount) {
                    val match = findInTree(node.getChild(index))
                    if (match != null) return match
                }
                return null
            }
            fun findAlert(): AccessibilityNodeInfo? {
                automation.clearCache()
                return automation.windows.asSequence().mapNotNull { findInTree(it.root) }.firstOrNull()
            }
            val visibleDeadline = SystemClock.elapsedRealtime() + 5000
            while (SystemClock.elapsedRealtime() < visibleDeadline) {
                automation.clearCache()
                if (findAlert() != null) break
                SystemClock.sleep(50)
            }
            val screenshot = File(context.getExternalFilesDir(null), "push-tray.png")
            FileOutputStream(screenshot).use { output -> automation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, output) }
            automation.clearCache()
            assertFalse("Awalingo alert must be visible: gate=${store.gate()} active=${manager.activeNotifications.size} root=${automation.rootInActiveWindow?.packageName} title=${manager.activeNotifications.firstOrNull()?.notification?.extras?.getString("android.title")}", findAlert() == null)
            // Copy completed bitmap output before tapping/cancelling the notification.
            automation.executeShellCommand("cp ${screenshot.absolutePath} /data/local/tmp/awalingo-push-tray.png").use { descriptor ->
                FileInputStream(descriptor.fileDescriptor).use { it.readBytes() }
            }
            var node: AccessibilityNodeInfo? = findAlert()
            while (node != null && !node.isClickable) node = node.parent
            assertTrue("A real tray click must dispatch the notification intent", node?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true)
            val launchDeadline = SystemClock.elapsedRealtime() + 10000
            while (SystemClock.elapsedRealtime() < launchDeadline) {
                automation.clearCache()
                if (automation.rootInActiveWindow?.packageName == context.packageName) break
                SystemClock.sleep(50)
            }
            assertEquals(context.packageName, automation.rootInActiveWindow?.packageName)

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
