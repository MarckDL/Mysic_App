package com.mysic.mysic

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Only the request identifier and deadline survive process death. The return reference stays in memory. */
internal class YouTubeLinkBridge(private val context: Context) {
    private val prefs by lazy { context.getSharedPreferences("youtube_link_pending", Context.MODE_PRIVATE) }
    private var channel: MethodChannel? = null
    private var pendingReturn: String? = null

    fun receive(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        if (uri.scheme != "https" || uri.host != context.getString(R.string.youtube_app_link_host) ||
            uri.port != -1 || uri.userInfo != null || uri.query != null ||
            uri.encodedPath != "/library/youtube/return" || uri.fragment.isNullOrEmpty() ||
            uri.toString().length > 512) return
        pendingReturn = uri.toString()
        channel?.invokeMethod("returnReady", null)
    }

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "com.mysic/connected_library").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                if (call.method == "takeReturn") {
                    val value = pendingReturn
                    pendingReturn = null
                    result.success(value)
                    return@setMethodCallHandler
                }
                val uid = call.argument<String>("uid")
                if (uid.isNullOrEmpty() || uid.length > 128) {
                    result.error("INVALID_ACCOUNT", "Cuenta inválida", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "load" -> result.success(prefs.getString(uid, null))
                    "save" -> {
                        val value = call.argument<String>("data")
                        if ((value?.length ?: 0) > 1024) result.error("INVALID_DATA", "Intento inválido", null)
                        else if (prefs.edit().putString(uid, value).commit()) result.success(null)
                        else result.error("STORAGE_ERROR", "No se pudo guardar el intento", null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
