package com.example.awalingo.push

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.example.awalingo.MainActivity
import com.example.awalingo.R
import org.json.JSONObject

class PushNotifications(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    fun createChannel() { manager.createNotificationChannel(NotificationChannel(CHANNEL, "Awalingo updates", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "Updates about your Awalingo activity" }) }
    fun status(): Map<String, Any> {
        createChannel()
        val granted = Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val channelEnabled = manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
        return mapOf("granted" to (granted && channelEnabled && NotificationManagerCompat.from(context).areNotificationsEnabled()), "permissionGranted" to granted, "channelEnabled" to channelEnabled)
    }
    fun post(payload: Map<String, String>): Boolean = synchronized(PushStore.lock) {
        if (!PushPolicy.accepts(payload, PushStore(context).gate()) || status()["granted"] != true) return@synchronized false
        val tag = PushPolicy.notificationTag(payload)
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_TAP
            data = Uri.Builder().scheme("awalingo-push").authority("notification").appendPath(tag).build()
            putExtra(EXTRA_PAYLOAD, JSONObject(payload).toString())
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_awalingo).setContentTitle(payload["title"]).setContentText(payload["body"])
            .setStyle(NotificationCompat.BigTextStyle().bigText(payload["body"]))
            .setContentIntent(pending).setAutoCancel(true).setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).build()
        try { manager.notify(tag, 0, notification); true } catch (_: SecurityException) { false }
    }
    fun cancelAll() = manager.cancelAll()
    companion object {
        const val CHANNEL = "awalingo_updates"
        const val ACTION_TAP = "com.example.awalingo.PUSH_TAP"
        const val EXTRA_PAYLOAD = "awalingo_push_payload"
    }
}
