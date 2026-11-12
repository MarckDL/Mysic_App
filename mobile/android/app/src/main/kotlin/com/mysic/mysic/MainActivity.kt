package com.mysic.mysic

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val playbackResolver = DevicePlaybackResolver()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        playbackResolver.close()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
