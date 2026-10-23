package com.example.awalingo.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class AwalingoMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        PushStore(this).token = token
        PushEvents.emit(mapOf("type" to "token"))
    }
    override fun onMessageReceived(message: RemoteMessage) {
        if (PushNotifications(this).post(message.data)) PushEvents.emit(mapOf("type" to "message", "payload" to message.data))
    }
}
