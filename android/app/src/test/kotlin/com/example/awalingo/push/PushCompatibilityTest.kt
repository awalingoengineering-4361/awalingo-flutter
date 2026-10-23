package com.example.awalingo.push

import android.content.Context
import android.provider.Settings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 25], manifest = Config.NONE)
class PushCompatibilityTest {
    @Test fun channelCreationAndStatusWorkOnSupportedAndroid7() {
        val context: Context = RuntimeEnvironment.getApplication()
        val notifications = PushNotifications(context)
        notifications.createChannel()
        assertEquals(true, notifications.status()["channelEnabled"])
    }
    @Test fun notificationSettingsAreAvailableBeforeAndroid8() {
        val context: Context = RuntimeEnvironment.getApplication()
        val intent = PushNotifications(context).settingsIntent()
        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, intent.action)
        assertEquals("package:${context.packageName}", intent.data.toString())
    }
}
