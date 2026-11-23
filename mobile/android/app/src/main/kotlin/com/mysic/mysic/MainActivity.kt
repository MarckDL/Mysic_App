package com.mysic.mysic

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val ytmSession by lazy { YtmSessionStore(this) }
    private var pendingLogin: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != YTM_LOGIN) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingLogin ?: return
        pendingLogin = null
        val cookie = if (resultCode == RESULT_OK) data?.getStringExtra("cookie") else null
        if (cookie != null) ytmSession.save(cookie)
        result.success(cookie)
    }

    // Lazy: the cache directory only exists once the activity is attached.
    private val playbackResolver by lazy {
        DevicePlaybackResolver(java.io.File(cacheDir, "resolved_sources.json"), filesDir)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Sesión de YouTube Music: la cookie vive cifrada en el teléfono.
        MethodChannel(messenger, "com.mysic/ytm").setMethodCallHandler { call, result ->
            when (call.method) {
                "login" -> {
                    if (pendingLogin != null) {
                        result.error("BUSY", "Ya hay un inicio de sesión abierto", null)
                    } else {
                        pendingLogin = result
                        startActivityForResult(Intent(this, YtmLoginActivity::class.java), YTM_LOGIN)
                    }
                }
                "load" -> result.success(ytmSession.load())
                "clear" -> {
                    ytmSession.clear()
                    android.webkit.CookieManager.getInstance().removeAllCookies { result.success(null) }
                }
                else -> result.notImplemented()
            }
        }
        // Estado para el widget de la pantalla de inicio. Se usa el contexto de la aplicación:
        // el motor puede seguir vivo con la actividad cerrada.
        val appContext = applicationContext
        MethodChannel(messenger, "com.mysic/widget").setMethodCallHandler { call, result ->
            if (call.method == "update") {
                MysicWidgetProvider.push(appContext, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(messenger, "com.mysic/audio_output").setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
            } else {
                val action = if (android.os.Build.VERSION.SDK_INT >= 29) {
                    android.provider.Settings.Panel.ACTION_VOLUME
                } else {
                    android.provider.Settings.ACTION_SOUND_SETTINGS
                }
                startActivity(android.content.Intent(action))
                result.success(null)
            }
        }
        // Compartir un enlace con el menú del sistema.
        MethodChannel(messenger, "com.mysic/share").setMethodCallHandler { call, result ->
            val text = call.argument<String>("text")
            if (call.method != "text") {
                result.notImplemented()
            } else if (text.isNullOrBlank()) {
                result.error("EMPTY", "No hay nada que compartir", null)
            } else {
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                    call.argument<String>("title")?.let { putExtra(Intent.EXTRA_TITLE, it) }
                }
                startActivity(Intent.createChooser(send, null))
                result.success(null)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DevicePlaybackResolver.CHANNEL,
        ).setMethodCallHandler(playbackResolver)
    }

    private companion object {
        const val YTM_LOGIN = 4711
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DevicePlaybackResolver.CHANNEL,
        ).setMethodCallHandler(null)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "com.mysic/audio_output").setMethodCallHandler(null)
        MethodChannel(messenger, "com.mysic/ytm").setMethodCallHandler(null)
        MethodChannel(messenger, "com.mysic/widget").setMethodCallHandler(null)
        MethodChannel(messenger, "com.mysic/share").setMethodCallHandler(null)
        playbackResolver.close()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
