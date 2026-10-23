package com.example.awalingo.push

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailabilityLight
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

object PushEvents {
    var sink: EventChannel.EventSink? = null
    fun emit(event: Map<String, Any>) { Handler(Looper.getMainLooper()).post { sink?.success(event) } }
}
class AndroidPushBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val store = PushStore(activity)
    private val notifications = PushNotifications(activity)
    private val methods = MethodChannel(messenger, "awalingo/push")
    private val events = EventChannel(messenger, "awalingo/push/events")
    private var permissionResult: MethodChannel.Result? = null
    init {
        notifications.createChannel()
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { PushEvents.sink = sink }
            override fun onCancel(arguments: Any?) { PushEvents.sink = null }
        })
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                "requestPermission" -> {
                    if (permissionResult != null) result.error("busy", "Permission request already open.", null)
                    else if (Build.VERSION.SDK_INT >= 33 && notifications.status()["permissionGranted"] != true) {
                        permissionResult = result
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST)
                    } else result.success(status())
                }
                "getToken" -> {
                    if (status()["available"] != true) result.error("unavailable", "Google Play services are unavailable.", null)
                    else {
                        FirebaseMessaging.getInstance().isAutoInitEnabled = true
                        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                            if (task.isSuccessful) { store.token = task.result; result.success(task.result) }
                            else result.error("token_unavailable", "Unable to register this device. Try again.", null)
                        }
                    }
                }
                "setSession" -> {
                    synchronized(PushStore.lock) {
                        val owner = call.argument<String>("ownerId")
                        val environment = call.argument<String>("environment") ?: ""
                        val enabled = call.argument<Boolean>("enabled") == true && !owner.isNullOrBlank() && environment.isNotBlank()
                        store.setGate(PushGate(owner, environment, enabled))
                        if (!enabled) notifications.cancelAll()
                    }
                    result.success(null)
                }
                "deleteToken" -> {
                    FirebaseMessaging.getInstance().isAutoInitEnabled = false
                    FirebaseMessaging.getInstance().deleteToken().addOnCompleteListener { task ->
                        if (task.isSuccessful) { store.token = null; result.success(null) }
                        else result.error("token_cleanup_failed", "Device cleanup will retry later.", null)
                    }
                }
                "cancelNotifications" -> { notifications.cancelAll(); result.success(null) }
                "getInitialTap" -> result.success(synchronized(PushStore.lock) { store.takeTap()?.takeIf { PushPolicy.accepts(it, store.gate()) } })
                "openSettings" -> {
                    activity.startActivity(notifications.settingsIntent())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun status() = notifications.status() + mapOf("available" to (GoogleApiAvailabilityLight.getInstance().isGooglePlayServicesAvailable(activity) == ConnectionResult.SUCCESS))
    fun permissionResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST) return false
        permissionResult?.success(status()); permissionResult = null; return true
    }
    fun handleIntent(intent: Intent?) {
        if (intent?.action != PushNotifications.ACTION_TAP) return
        val raw = intent.getStringExtra(PushNotifications.EXTRA_PAYLOAD) ?: return
        intent.removeExtra(PushNotifications.EXTRA_PAYLOAD)
        synchronized(PushStore.lock) {
            val payload = try { val obj = JSONObject(raw); obj.keys().asSequence().associateWith { obj.getString(it) } } catch (_: Exception) { return }
            if (!PushPolicy.accepts(payload, store.gate())) return
            store.saveTap(payload)
            PushEvents.emit(mapOf("type" to "tap"))
        }
    }
    fun dispose() { methods.setMethodCallHandler(null); events.setStreamHandler(null); PushEvents.sink = null; permissionResult?.error("cancelled", "Activity closed.", null); permissionResult = null }
    companion object { private const val REQUEST = 7701 }
}
