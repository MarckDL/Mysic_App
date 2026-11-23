package com.mysic.mysic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaControllerCompat
import android.view.KeyEvent
import android.widget.RemoteViews
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Widget de la pantalla de inicio: portada de fondo, título, anterior, pausa/reproducir, siguiente y
 * Me gusta. La app (Flutter) le envía el estado; los botones actúan sobre la sesión de medios o,
 * en el caso del corazón, le piden a la app que marque la canción.
 */
class MysicWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) manager.updateAppWidget(id, build(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_PLAY_PAUSE -> sendKey(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            ACTION_NEXT -> sendKey(context, KeyEvent.KEYCODE_MEDIA_NEXT)
            ACTION_PREVIOUS -> sendKey(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            ACTION_LIKE -> like(context, goAsync())
            else -> super.onReceive(context, intent)
        }
    }

    companion object {
        private const val ACTION_PLAY_PAUSE = "com.mysic.mysic.widget.PLAY_PAUSE"
        private const val ACTION_NEXT = "com.mysic.mysic.widget.NEXT"
        private const val ACTION_PREVIOUS = "com.mysic.mysic.widget.PREVIOUS"
        private const val ACTION_LIKE = "com.mysic.mysic.widget.LIKE"
        private const val PREFS = "mysic_widget"
        private const val COVER_FILE = "widget_cover.jpg"

        // Solo se descargan portadas de los servidores de imágenes de YouTube.
        private val ART_HOSTS = listOf("googleusercontent.com", "ytimg.com", "ggpht.com")

        /** Recibe el estado que publica la app y repinta el widget. */
        fun push(context: Context, args: Map<*, *>) {
            val app = context.applicationContext
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val art = args["art"] as? String
            val artChanged = art != prefs.getString("art", null)
            prefs.edit()
                .putBoolean("has", args["has"] == true)
                .putString("title", args["title"] as? String)
                .putString("artist", args["artist"] as? String)
                .putBoolean("playing", args["playing"] == true)
                .putBoolean("liked", args["liked"] == true)
                .putString("art", art)
                .apply()
            if (artChanged) {
                File(app.filesDir, COVER_FILE).delete()
                if (art != null) downloadCover(app, art)
            }
            refresh(app)
        }

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, MysicWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val views = build(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun build(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val has = prefs.getBoolean("has", false)
            val views = RemoteViews(context.packageName, R.layout.mysic_widget)
            views.setTextViewText(
                R.id.widget_title,
                if (has) prefs.getString("title", "").orEmpty() else context.getString(R.string.mysic_widget_idle_title),
            )
            views.setTextViewText(
                R.id.widget_artist,
                if (has) prefs.getString("artist", "").orEmpty() else context.getString(R.string.mysic_widget_idle_subtitle),
            )
            views.setImageViewResource(
                R.id.widget_play,
                if (prefs.getBoolean("playing", false)) R.drawable.ic_w_pause else R.drawable.ic_w_play,
            )
            views.setImageViewResource(
                R.id.widget_like,
                if (prefs.getBoolean("liked", false)) R.drawable.ic_w_heart_on else R.drawable.ic_w_heart,
            )
            val cover = File(context.filesDir, COVER_FILE)
            if (has && cover.exists()) {
                views.setImageViewBitmap(R.id.widget_cover, BitmapFactory.decodeFile(cover.path))
            } else {
                views.setImageViewBitmap(R.id.widget_cover, null)
            }
            views.setOnClickPendingIntent(R.id.widget_like, action(context, ACTION_LIKE, 1))
            views.setOnClickPendingIntent(R.id.widget_prev, action(context, ACTION_PREVIOUS, 2))
            views.setOnClickPendingIntent(R.id.widget_play, action(context, ACTION_PLAY_PAUSE, 3))
            views.setOnClickPendingIntent(R.id.widget_next, action(context, ACTION_NEXT, 4))
            val open = PendingIntent.getActivity(
                context,
                5,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.widget_root, open)
            return views
        }

        private fun action(context: Context, action: String, code: Int): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                code,
                Intent(context, MysicWidgetProvider::class.java).setAction(action),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        private fun sendKey(context: Context, code: Int) {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
        }

        /** El corazón cambia al instante y la app confirma (o corrige) el estado real. */
        private fun like(context: Context, pending: BroadcastReceiver.PendingResult) {
            val app = context.applicationContext
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!prefs.getBoolean("has", false)) {
                pending.finish()
                return
            }
            prefs.edit().putBoolean("liked", !prefs.getBoolean("liked", false)).apply()
            refresh(app)
            lateinit var browser: MediaBrowserCompat
            browser = MediaBrowserCompat(
                app,
                ComponentName(app, "com.ryanheise.audioservice.AudioService"),
                object : MediaBrowserCompat.ConnectionCallback() {
                    override fun onConnected() {
                        try {
                            MediaControllerCompat(app, browser.sessionToken)
                                .transportControls.sendCustomAction("like", null)
                        } finally {
                            browser.disconnect()
                            pending.finish()
                        }
                    }

                    override fun onConnectionFailed() {
                        // Sin sesión activa no hay a quién pedírselo: se deshace el cambio.
                        prefs.edit().putBoolean("liked", !prefs.getBoolean("liked", false)).apply()
                        refresh(app)
                        pending.finish()
                    }
                },
                null,
            )
            Handler(Looper.getMainLooper()).post { browser.connect() }
        }

        private fun downloadCover(context: Context, url: String) {
            val uri = Uri.parse(url)
            val host = uri.host.orEmpty()
            if (uri.scheme != "https" || ART_HOSTS.none { host == it || host.endsWith(".$it") }) return
            Thread {
                try {
                    val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 8000
                        readTimeout = 8000
                    }
                    val bytes = connection.inputStream.use { it.readBytes() }
                    if (bytes.size > 3_000_000) return@Thread
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    var sample = 1
                    while (bounds.outWidth / sample > 800) sample *= 2
                    val bitmap = BitmapFactory.decodeByteArray(
                        bytes,
                        0,
                        bytes.size,
                        BitmapFactory.Options().apply { inSampleSize = sample },
                    ) ?: return@Thread
                    File(context.filesDir, COVER_FILE).outputStream().use {
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 88, it)
                    }
                    // Si mientras tanto cambió la canción, esta portada ya no vale.
                    val current = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("art", null)
                    if (current == url) refresh(context) else File(context.filesDir, COVER_FILE).delete()
                } catch (_: Exception) {
                    // Sin portada se ve el fondo liso: el widget sigue funcionando.
                }
            }.start()
        }
    }
}
