package com.mysic.mysic

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Resuelve el audio de una canción con UNA petición `player` del cliente VISIONOS, desde la IP del
 * teléfono: sin descifrado ni token (igual que el resolvedor del escritorio, `resolver.rs`). Es
 * mucho más rápido que NewPipe (~0,1 s frente a ~1 s), pero es una API no oficial: por eso el
 * perfil del cliente es un dato (se puede sustituir con `visionos_client.json`) y quien lo llama
 * conserva NewPipe como respaldo.
 */
internal class VisionOsClient(client: OkHttpClient, private val dir: File?) {
    data class Profile(
        val clientName: String = "VISIONOS",
        val clientVersion: String = "1.02",
        val clientId: String = "101",
        val osName: String = "visionOS",
        val osVersion: String = "26.5.23O471",
        val deviceMake: String = "Apple",
        val deviceModel: String = "RealityDevice17,1",
        val userAgent: String =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 " +
                "(KHTML, like Gecko) Version/26.0 Safari/605.1.15",
        val platform: String = "MOBILE",
    ) {
        /** Un perfil externo solo vale si todo es texto corto, imprimible y no vacío. */
        fun isValid(): Boolean = listOf(
            clientName, clientVersion, clientId, osName, osVersion,
            deviceMake, deviceModel, userAgent, platform,
        ).all { it.isNotBlank() && it.length <= 300 && it.none(Char::isISOControl) } &&
            clientId.all(Char::isDigit)
    }

    class Format(
        val url: String,
        val mimeType: String,
        val contentLength: Long?,
        val itag: Int,
        val bitrate: Long,
    )

    /** El cliente no pudo dar una URL; [code] es estable para el registro. */
    class DirectFailure(val code: String, message: String) : Exception(message)

    // Comparte conexiones con el resto de peticiones; solo cambia el plazo.
    private val http = client.newBuilder().callTimeout(DIRECT_TIMEOUT_MS, TimeUnit.MILLISECONDS).build()

    @Volatile
    private var profile: Profile = loadProfile()
    private var visitor: String? = null
    private var visitorAt = 0L

    /** Cabecera `User-Agent` con la que hay que pedir el audio (va ligada al cliente). */
    val userAgent: String get() = profile.userAgent

    fun resolve(videoId: String): Format {
        var visitorData = visitorData(force = false)
        var response = requestPlayer(videoId, visitorData)
        // YouTube pide "confirmar que no eres un bot" cuando el visitante ya no vale: se renueva una vez.
        if (status(response) == "LOGIN_REQUIRED") {
            visitorData = visitorData(force = true)
            response = requestPlayer(videoId, visitorData)
        }
        val status = status(response)
        if (status != "OK") {
            val reason = response.optJSONObject("playabilityStatus")?.optString("reason").orEmpty()
            throw DirectFailure(status.ifEmpty { "UNKNOWN" }, "$status $reason".trim())
        }
        return pickAudio(response) ?: throw DirectFailure("NO_AUDIO", "sin formato de audio con URL")
    }

    /** Calienta lo que tarda más en el primer toque del día: el visitante y la conexión TLS. */
    fun warm() {
        runCatching { visitorData(force = false) }
    }

    private fun status(response: JSONObject): String =
        response.optJSONObject("playabilityStatus")?.optString("status").orEmpty()

    @Synchronized
    private fun visitorData(force: Boolean): String {
        val now = System.currentTimeMillis()
        if (!force) {
            visitor?.let { if (now - visitorAt < VISITOR_TTL_MS) return it }
            readSavedVisitor()?.let { (value, at) ->
                if (now - at < VISITOR_TTL_MS) {
                    visitor = value
                    visitorAt = at
                    return value
                }
            }
        }
        val request = Request.Builder()
            .url(SW_DATA_URL)
            .header("Accept-Language", "en-US")
            .header("User-Agent", profile.userAgent)
            .header("Accept", "*/*")
            .header("Referer", "https://www.youtube.com/sw.js")
            .header("Cookie", "PREF=tz=America.Lima;VISITOR_INFO1_LIVE=abcdefghijk;")
            .build()
        val text = http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw DirectFailure("VISITOR_UNAVAILABLE", "HTTP ${response.code}")
            response.body?.string().orEmpty()
        }
        val value = parseVisitor(text)
        visitor = value
        visitorAt = now
        saveVisitor(value, now)
        return value
    }

    private fun requestPlayer(videoId: String, visitorData: String): JSONObject {
        val p = profile
        val body = JSONObject()
            .put("videoId", videoId)
            .put("racyCheckOk", true)
            .put("contentCheckOk", true)
            .put(
                "context",
                JSONObject()
                    .put(
                        "client",
                        JSONObject()
                            .put("hl", "en")
                            .put("gl", "US")
                            .put("visitorData", visitorData)
                            .put("clientName", p.clientName)
                            .put("clientVersion", p.clientVersion)
                            .put("osName", p.osName)
                            .put("osVersion", p.osVersion)
                            .put("userAgent", p.userAgent)
                            .put("platform", p.platform)
                            .put("deviceMake", p.deviceMake)
                            .put("deviceModel", p.deviceModel),
                    )
                    .put("user", JSONObject().put("lockedSafetyMode", false))
                    .put("request", JSONObject().put("useSsl", true)),
            )
        val request = Request.Builder()
            .url(PLAYER_URL)
            .header("User-Agent", p.userAgent)
            .header("Origin", "https://www.youtube.com")
            .header("X-Goog-Visitor-Id", visitorData)
            .header("X-Youtube-Client-Name", p.clientId)
            .header("X-Youtube-Client-Version", p.clientVersion)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        return http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw DirectFailure("UNAVAILABLE", "HTTP ${response.code}")
            JSONObject(response.body?.string().orEmpty())
        }
    }

    // ---- Perfil y visitante en disco ----

    private fun loadProfile(): Profile {
        val file = dir?.let { File(it, PROFILE_FILE) } ?: return Profile()
        return runCatching {
            if (!file.exists() || file.length() > 16 * 1024) return Profile()
            val json = JSONObject(file.readText())
            val base = Profile()
            val candidate = Profile(
                clientName = json.optString("clientName", base.clientName),
                clientVersion = json.optString("clientVersion", base.clientVersion),
                clientId = json.optString("clientId", base.clientId),
                osName = json.optString("osName", base.osName),
                osVersion = json.optString("osVersion", base.osVersion),
                deviceMake = json.optString("deviceMake", base.deviceMake),
                deviceModel = json.optString("deviceModel", base.deviceModel),
                userAgent = json.optString("userAgent", base.userAgent),
                platform = json.optString("platform", base.platform),
            )
            if (candidate.isValid()) candidate else base
        }.getOrDefault(Profile())
    }

    private fun readSavedVisitor(): Pair<String, Long>? {
        val file = dir?.let { File(it, VISITOR_FILE) } ?: return null
        return runCatching {
            if (!file.exists()) return null
            val json = JSONObject(file.readText())
            val value = json.optString("v")
            if (value.isEmpty()) null else value to json.optLong("at")
        }.getOrNull()
    }

    private fun saveVisitor(value: String, at: Long) {
        val file = dir?.let { File(it, VISITOR_FILE) } ?: return
        runCatching { file.writeText(JSONObject().put("v", value).put("at", at).toString()) }
    }

    companion object {
        private const val PLAYER_URL = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false&alt=json"
        private const val SW_DATA_URL = "https://www.youtube.com/sw.js_data"
        private const val VISITOR_TTL_MS = 12 * 60 * 60 * 1000L
        private const val DIRECT_TIMEOUT_MS = 4_000L
        private const val PROFILE_FILE = "visionos_client.json"
        private const val VISITOR_FILE = "visionos_visitor.json"

        /** `visitorData` de la respuesta de `/sw.js_data` (JSPB con prefijo `)]}'`): `[0][2][0][0][13]`. */
        internal fun parseVisitor(text: String): String {
            val body = text.removePrefix(")]}'")
            if (body == text) throw DirectFailure("VISITOR_UNAVAILABLE", "formato inesperado")
            return runCatching {
                JSONArray(body).getJSONArray(0).getJSONArray(2).getJSONArray(0).getJSONArray(0).getString(13)
            }.getOrNull()?.takeIf { it.isNotEmpty() }
                ?: throw DirectFailure("VISITOR_UNAVAILABLE", "sin visitorData")
        }

        /**
         * Mejor formato de solo audio con URL directa: itag 140 (AAC en mp4, el más compatible) y, si
         * no hay, el de mayor bitrate entre mp4 y webm.
         */
        internal fun pickAudio(response: JSONObject): Format? {
            val formats = response.optJSONObject("streamingData")?.optJSONArray("adaptiveFormats") ?: return null
            val candidates = mutableListOf<Format>()
            for (i in 0 until formats.length()) {
                val format = formats.optJSONObject(i) ?: continue
                val mime = format.optString("mimeType")
                val url = format.optString("url")
                if (url.isEmpty() || !(mime.startsWith("audio/mp4") || mime.startsWith("audio/webm"))) continue
                candidates += Format(
                    url = url,
                    mimeType = mime.substringBefore(';'),
                    contentLength = format.optString("contentLength").toLongOrNull(),
                    itag = format.optInt("itag"),
                    bitrate = format.optLong("bitrate"),
                )
            }
            return candidates.sortedWith(
                compareBy<Format> { it.itag != 140 }.thenByDescending { it.bitrate },
            ).firstOrNull()
        }
    }
}
