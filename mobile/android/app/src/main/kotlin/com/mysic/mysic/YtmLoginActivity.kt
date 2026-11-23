package com.mysic.mysic

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout

/**
 * Inicio de sesión de YouTube Music en una ventana propia: se entra con la cuenta de Google en la
 * página oficial y, al llegar a music.youtube.com, se devuelve la cookie de la sesión. Mysic no ve
 * la contraseña; solo recibe la cookie que el navegador ya guardó.
 */
class YtmLoginActivity : Activity() {
    private var web: WebView? = null
    private var handling = false
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val view = WebView(this)
        web = view
        view.setBackgroundColor(Color.BLACK)
        view.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        setContentView(FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            fitsSystemWindows = true
            addView(view)
        })
        val cookies = CookieManager.getInstance()
        cookies.setAcceptCookie(true)
        cookies.setAcceptThirdPartyCookies(view, true)
        view.settings.javaScriptEnabled = true
        view.settings.domStorageEnabled = true
        // Google rechaza el acceso desde la marca "wv" de las vistas incrustadas.
        view.settings.userAgentString = view.settings.userAgentString.replace("; wv", "")
        view.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                if (url != null && url.startsWith(MUSIC_URL)) collect()
            }
        }
        // Siempre desde cero: así se entra con la cuenta elegida y no con una sesión anterior.
        cookies.removeAllCookies {
            cookies.flush()
            view.loadUrl(LOGIN_URL)
        }
    }

    // La redirección que llega aquí fija las cookies, a veces un instante después de cargar la página.
    private fun collect(attempt: Int = 0) {
        if (handling && attempt == 0) return
        handling = true
        val cookie = CookieManager.getInstance().getCookie(MUSIC_URL).orEmpty()
        // Solo los nombres de las cookies, nunca sus valores.
        android.util.Log.d(
            "YtmLogin",
            "intento=$attempt nombres=" + cookie.split(";").joinToString(",") { it.substringBefore("=").trim() },
        )
        if (cookie.contains("SAPISID=")) {
            setResult(RESULT_OK, Intent().putExtra("cookie", cookie))
            finish()
        } else if (attempt < 6) {
            handler.postDelayed({ collect(attempt + 1) }, 500)
        } else {
            handling = false
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        web?.let {
            (it.parent as? ViewGroup)?.removeView(it)
            it.destroy()
        }
        web = null
        super.onDestroy()
    }

    companion object {
        const val MUSIC_URL = "https://music.youtube.com/"
        const val LOGIN_URL =
            "https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&uilel=3&passive=true" +
                "&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop" +
                "%26hl%3Des%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F%26feature%3D__FEATURE__&hl=es"
    }
}
