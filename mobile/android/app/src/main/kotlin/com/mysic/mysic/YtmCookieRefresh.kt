package com.mysic.mysic

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * Renovación de la sesión de YouTube Music, como la de Limusic (`freshYouTubeJar`).
 *
 * La cookie que guarda Mysic es una foto: Google rota sus fichas de corta vida (SIDTS…) y, pasado un
 * tiempo, rechaza la copia con 401/403. El almacén de cookies de la vista web, en cambio, sigue vivo:
 * al cargar music.youtube.com en una vista oculta, YouTube entrega las cookies rotadas. Si son de la
 * misma cuenta (mismo SAPISID) y distintas de las guardadas, sustituyen a estas.
 */
object YtmCookieRefresh {
    private const val MUSIC_URL = "https://music.youtube.com/"
    private const val TIMEOUT_MS = 45_000L
    private const val POLLS = 8
    private const val POLL_MS = 500L

    /** El SAPISID de la cookie: uno por inicio de sesión de Google; null si no hay sesión. */
    fun sapisid(cookie: String?): String? {
        val parts = cookie?.split(';')?.map { it.trim() } ?: return null
        for (name in listOf("SAPISID=", "__Secure-3PAPISID=")) {
            val value = parts.firstOrNull { it.startsWith(name) }?.removePrefix(name)
            if (!value.isNullOrEmpty()) return value
        }
        return null
    }

    private fun sameJar(a: String, b: String): Boolean {
        fun pairs(s: String) = s.split(';').map { it.trim() }.filter { it.isNotEmpty() }.sorted()
        return pairs(a) == pairs(b)
    }

    /**
     * Pide las cookies rotadas. [done] recibe la cookie nueva o null si no hay nada más fresco (otra
     * cuenta, sin sesión, sin conexión o sin vista web). Se llama una sola vez, en el hilo principal.
     */
    fun refresh(context: Context, current: String, done: (String?) -> Unit) {
        val handler = Handler(Looper.getMainLooper())
        val account = sapisid(current)
        if (account == null) {
            done(null)
            return
        }
        val web = try {
            WebView(context)
        } catch (_: Exception) {
            done(null)
            return
        }
        var finished = false
        fun finish(result: String?) {
            if (finished) return
            finished = true
            handler.removeCallbacksAndMessages(null)
            try {
                web.stopLoading()
                web.destroy()
            } catch (_: Exception) {
                // Ya destruida: no hay nada que liberar.
            }
            done(result)
        }
        fun poll(attempt: Int) {
            if (finished) return
            val jar = CookieManager.getInstance().getCookie(MUSIC_URL).orEmpty()
            if (sapisid(jar) == account && !sameJar(jar, current)) {
                finish(jar)
            } else if (attempt < POLLS) {
                // Llegar a la página y haber rotado no son el mismo instante.
                handler.postDelayed({ poll(attempt + 1) }, POLL_MS)
            } else {
                finish(null)
            }
        }
        CookieManager.getInstance().setAcceptCookie(true)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        // La misma identidad que la ventana de inicio de sesión, para que la cuenta no vea otro navegador.
        web.settings.userAgentString = web.settings.userAgentString.replace("; wv", "")
        web.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                if (url != null && url.startsWith(MUSIC_URL)) poll(0)
            }
        }
        handler.postDelayed({ finish(null) }, TIMEOUT_MS)
        web.loadUrl(MUSIC_URL)
    }
}
