package com.mysic.mysic

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val youtubeLink by lazy { YouTubeLinkBridge(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        youtubeLink.receive(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        youtubeLink.receive(intent)
    }

    private val playbackResolver = DevicePlaybackResolver()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        youtubeLink.attach(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mysic/history").setMethodCallHandler { call, result ->
            val uid = call.argument<String>("uid")
            if (uid == null || uid.length > 128) {
                result.error("INVALID_ACCOUNT", "Cuenta inválida", null)
            } else {
                val preferences = getSharedPreferences("history_pending", MODE_PRIVATE)
                when (call.method) {
                    "load" -> result.success(preferences.getString(uid, "{}"))
                    "save" -> {
                        val data = call.argument<String>("data")
                        if (data == null || data.length > 262144) result.error("INVALID_DATA", "Cola inválida", null)
                        else { preferences.edit().putString(uid, data).apply(); result.success(null) }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DevicePlaybackResolver.CHANNEL,
        ).setMethodCallHandler(playbackResolver)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DevicePlaybackResolver.CHANNEL,
        ).setMethodCallHandler(null)
        youtubeLink.detach()
        playbackResolver.close()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
