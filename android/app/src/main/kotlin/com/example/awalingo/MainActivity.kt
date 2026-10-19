package com.example.awalingo

import android.content.Intent
import com.example.awalingo.push.AndroidPushBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var pushBridge: AndroidPushBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pushBridge = AndroidPushBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        pushBridge?.handleIntent(intent)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pushBridge?.handleIntent(intent)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (pushBridge?.permissionResult(requestCode) != true) super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pushBridge?.dispose(); pushBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
