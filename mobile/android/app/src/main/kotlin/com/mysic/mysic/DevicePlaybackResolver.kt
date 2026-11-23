package com.mysic.mysic

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import okhttp3.Request
import org.schabi.newpipe.extractor.MediaFormat
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException
import org.schabi.newpipe.extractor.exceptions.SignInConfirmNotBotException
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.net.URI
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal class DevicePlaybackResolver(
    // Where resolved sources survive a restart; null keeps them in memory only.
    private val store: File? = null,
    // Private app files: experimental flags, the client profile and the visitor.
    private val filesDir: File? = null,
) : MethodChannel.MethodCallHandler, Closeable {
    private data class StageTimings(
        val queueMs: Long,
        val extractorMs: Long,
        val formatsMs: Long,
        val validationMs: Long,
        val totalMs: Long,
    )

    private data class CachedSource(
        val url: String,
        val mimeType: String,
        val expiresAtMillis: Long,
        val cacheHit: Boolean = false,
        val timings: StageTimings? = null,
        // Total size and the User-Agent the URL was issued for (direct client only).
        val contentLength: Long? = null,
        val userAgent: String? = null,
    )

    private val initialized = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val downloader = ExtractorDownloader()
    private val validationClient = OkHttpClient.Builder()
        .callTimeout(VALIDATION_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        .connectTimeout(VALIDATION_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        .readTimeout(VALIDATION_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()
    private val vision = VisionOsClient(validationClient, filesDir)
    // Streaming has no whole-call deadline (a paused player holds the connection) and its own
    // dispatcher, so cancelling a resolution never cuts a song that is playing.
    private val streamClient = validationClient.newBuilder()
        .dispatcher(okhttp3.Dispatcher())
        .callTimeout(0, TimeUnit.MILLISECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()
    private val proxy: LocalAudioProxy? by lazy {
        runCatching { LocalAudioProxy(streamClient, ::proxySource) }
            .onFailure { Log.w(LOG_TAG, "proxy_start_failed ${it.javaClass.simpleName}") }
            .getOrNull()
    }
    // Hasta cuándo no se calienta nada porque YouTube pide confirmar que no es un bot.
    @Volatile
    private var blockedUntil = 0L
    @Volatile
    private var directFailures = 0
    @Volatile
    private var directDisabledUntil = 0L
    // The flights lock also protects cached results and active work.
    private val cache = object : LinkedHashMap<String, CachedSource>(CACHE_LIMIT, 0.75f, true) {
        override fun removeEldestEntry(
            eldest: MutableMap.MutableEntry<String, CachedSource>?,
        ): Boolean = size > CACHE_LIMIT
    }
    private val flights = mutableMapOf<String, CompletableFuture<CachedSource>>()
    private var activeFlight: CompletableFuture<CachedSource>? = null
    private var prefetchSourceId: String? = null
    private var prefetchTask: CompletableFuture<CachedSource>? = null

    init {
        // Off the main thread, and ahead of any resolution on the same executor.
        executor.execute(::loadStore)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "warmUp" -> {
                executor.execute {
                    if (flag(FAST_FLAG)) runCatching { vision.warm() }
                    runCatching { initializeExtractor() }
                    if (flag(PROXY_FLAG)) proxy
                    mainHandler.post { result.success(null) }
                }
            }
            "resolve" -> resolveCall(call, result)
            "prefetch" -> prefetchCall(call, result)
            "cancelPrefetch" -> {
                cancelPrefetch()
                result.success(null)
            }
            "warm" -> {
                warm(call.argument<List<String>>("sourceIds").orEmpty())
                result.success(null)
            }
            "touch" -> {
                touch(call.argument<String>("sourceId"))
                result.success(null)
            }
            "clear" -> {
                Log.i(LOG_TAG, "device_clear")
                cancelAll()
                runCatching { executor.execute { runCatching { store?.delete() } } }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun resolveCall(call: MethodCall, result: MethodChannel.Result) {
        val sourceId = call.argument<String>("sourceId")
        if (!isValidSourceId(sourceId)) {
            result.error("INVALID_SOURCE", "Invalid source id", null)
            return
        }
        val id = sourceId!!
        val refresh = call.argument<Boolean>("refresh") == true
        if (prefetchSourceId == id && !refresh) {
            // The foreground request takes ownership of the prefetched flight.
            prefetchSourceId = null
            prefetchTask = null
        } else {
            cancelPrefetch()
        }
        synchronized(flights) {
            val obsolete = flights.keys.filter { it != id || refresh }
            for (obsoleteId in obsolete) cancelFlight(obsoleteId, flights.getValue(obsoleteId))
            if (refresh) cache.remove(id)
        }
        val startedAt = SystemClock.elapsedRealtime()
        // A tap does not wait for the tail probe (one extra round trip, ~0.6 s
        // measured): if the chosen stream turns out to be broken the player
        // comes back with refresh=true, and that retry does validate.
        resolveSingleFlight(id, validate = refresh, direct = !refresh).whenComplete { source, error ->
            val duration = SystemClock.elapsedRealtime() - startedAt
            if (error == null && source != null) {
                blockedUntil = 0L
                // After a failure (refresh) the player goes straight to the origin, never through
                // the proxy, so a broken proxy cannot trap a song in a retry loop.
                val local = if (!refresh && flag(PROXY_FLAG)) proxy else null
                Log.i(
                    LOG_TAG,
                    "device_resolution success=true durationMs=$duration cacheHit=${source.cacheHit}" +
                        source.timings?.let {
                            " queueMs=${it.queueMs} extractorMs=${it.extractorMs}" +
                                " formatsMs=${it.formatsMs} validationMs=${it.validationMs}" +
                                " totalMs=${it.totalMs}"
                        }.orEmpty(),
                )
                mainHandler.post {
                    result.success(
                        mapOf(
                            "url" to (local?.urlFor(id) ?: source.url),
                            "headers" to if (local == null && source.userAgent != null) {
                                mapOf("User-Agent" to source.userAgent)
                            } else {
                                emptyMap()
                            },
                            "mimeType" to source.mimeType,
                            "expiresAtMillis" to source.expiresAtMillis,
                            "cacheHit" to source.cacheHit,
                            "timings" to source.timings?.let(::timingsMap),
                        ),
                    )
                }
            } else {
                Log.w(
                    LOG_TAG,
                    "device_resolution success=false durationMs=$duration " +
                        "reason=${error?.javaClass?.simpleName ?: "Unknown"}",
                )
                // "No disponible" desde el extractor, justo después de que el cliente directo
                // devolviera LOGIN_REQUIRED, es YouTube pidiendo confirmar que no es un bot a
                // esta red: se avisa distinto y se dejan de lanzar calentados un rato.
                // Un vídeo borrado o privado también da "no disponible": solo cuenta como bloqueo
                // si el cliente directo viene fallando (está en pausa tras tres fallos seguidos).
                val now = System.currentTimeMillis()
                // El extractor lo dice con nombre propio cuando YouTube pide confirmar que no es un bot.
                val blocked = error is SignInConfirmNotBotException ||
                    (error is ContentNotAvailableException &&
                        (directDisabledUntil > now || directFailures > 0))
                if (blocked) blockedUntil = now + BLOCK_PAUSE_MS
                mainHandler.post {
                    result.error(
                        if (blocked) "RESOLUTION_BLOCKED" else "RESOLUTION_FAILED",
                        "No complete device playback source was available",
                        null,
                    )
                }
            }
        }
    }

    private fun prefetchCall(call: MethodCall, result: MethodChannel.Result) {
        val sourceId = call.argument<String>("sourceId")
        if (!isValidSourceId(sourceId) || closed.get()) {
            result.success(null)
            return
        }
        cancelPrefetch()
        val id = sourceId!!
        if (synchronized(flights) { flights.containsKey(id) }) {
            // Prefetch must not take ownership of a foreground resolution.
            result.success(null)
            return
        }
        prefetchSourceId = id
        val completion = resolveSingleFlight(id)
        prefetchTask = completion
        completion.whenComplete { source, _ ->
            if (source != null) prefetchHead(id)
            mainHandler.post {
                if (prefetchTask === completion) {
                    prefetchSourceId = null
                    prefetchTask = null
                }
                result.success(null)
            }
        }
    }

    // Resolves a few visible tracks in the background so that tapping one is a
    // cache hit. These flights have no owner: a foreground resolve of another
    // track cancels them (see resolveCall), and one of the same track joins it.
    private fun warm(sourceIds: List<String>) {
        // Con YouTube pidiendo confirmar que no es un bot, cada calentado fallaría y
        // sumaría peticiones: se espera a que un toque de verdad vuelva a funcionar.
        if (closed.get() || System.currentTimeMillis() < blockedUntil) return
        sourceIds.asSequence()
            .filter(::isValidSourceId)
            .distinct()
            .take(WARM_LIMIT)
            .forEach { id ->
                // Sin sonda del final: son hasta 12 resoluciones en serie y la descarga del primer
                // tramo ya comprueba que la URL responde (si no, se renueva al tocar).
                resolveSingleFlight(id, validate = false).whenComplete { source, error ->
                    if (source != null) prefetchHead(id)
                    Log.i(
                        LOG_TAG,
                        "device_warm success=${error == null} cacheHit=${source?.cacheHit}" +
                            " totalMs=${source?.timings?.totalMs}" +
                            " reason=${error?.javaClass?.simpleName}",
                    )
                }
            }
    }

    // The finger is already on this track: resolve it now, ahead of other background
    // work (their flights are cancelled, as a real tap would do) and without the tail
    // probe, so a tap that follows joins this flight instead of waiting for validation.
    private fun touch(sourceId: String?) {
        if (closed.get() || !isValidSourceId(sourceId)) return
        val id = sourceId!!
        if (prefetchSourceId != id) cancelPrefetch()
        synchronized(flights) {
            val obsolete = flights.keys.filter { it != id }
            for (obsoleteId in obsolete) cancelFlight(obsoleteId, flights.getValue(obsoleteId))
        }
        val startedAt = SystemClock.elapsedRealtime()
        resolveSingleFlight(id, validate = false).whenComplete { source, error ->
            if (source != null) prefetchHead(id)
            Log.i(
                LOG_TAG,
                "device_touch success=${error == null} cacheHit=${source?.cacheHit}" +
                    " durationMs=${SystemClock.elapsedRealtime() - startedAt}" +
                    " reason=${error?.javaClass?.simpleName}",
            )
        }
    }

    // Background work (warm, prefetch) validates by default: it has time to.
    private fun resolveSingleFlight(
        sourceId: String,
        validate: Boolean = true,
        direct: Boolean = true,
    ): CompletableFuture<CachedSource> {
        synchronized(flights) {
            cached(sourceId)?.let { return CompletableFuture.completedFuture(it) }
            flights[sourceId]?.let { return it }
            val queuedAt = SystemClock.elapsedRealtime()
            val future = CompletableFuture<CachedSource>()
            flights[sourceId] = future
            executor.execute {
                try {
                    synchronized(flights) {
                        if (flights[sourceId] !== future) return@execute
                        activeFlight = future
                    }
                    future.complete(
                        resolveUncached(sourceId, queuedAt, future, validate, direct),
                    )
                } catch (error: Throwable) {
                    future.completeExceptionally(error)
                } finally {
                    synchronized(flights) {
                        if (activeFlight === future) activeFlight = null
                        flights.remove(sourceId, future)
                    }
                }
            }
            return future
        }
    }

    private fun cached(sourceId: String): CachedSource? {
        val now = System.currentTimeMillis()
        val source = cache[sourceId]
        if (source != null && source.expiresAtMillis > now + EXPIRY_MARGIN_MS) {
            return source.copy(cacheHit = true, timings = null)
        }
        cache.remove(sourceId)
        return null
    }

    private fun resolveUncached(
        sourceId: String,
        queuedAt: Long,
        flight: CompletableFuture<CachedSource>,
        validate: Boolean,
        direct: Boolean,
    ): CachedSource {
        fun checkCurrent() {
            check(!closed.get() && !flight.isCancelled) {
                "Resolution cancelled"
            }
        }
        checkCurrent()
        val startedAt = SystemClock.elapsedRealtime()
        if (direct && flag(FAST_FLAG) && System.currentTimeMillis() >= directDisabledUntil) {
            resolveDirect(sourceId, queuedAt, startedAt, flight, validate)?.let { return it }
            checkCurrent()
        }
        initializeExtractor()
        val extractorStarted = SystemClock.elapsedRealtime()
        val extractor = ServiceList.YouTube.getStreamExtractor(
            "https://www.youtube.com/watch?v=$sourceId",
        )
        extractor.fetchPage()
        checkCurrent()
        val extractorMs = SystemClock.elapsedRealtime() - extractorStarted
        val formatsStarted = SystemClock.elapsedRealtime()
        val candidates = extractor.audioStreams
            .asSequence()
            .filter { it.isUrl }
            .filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }
            .filter { isAllowedMediaUrl(it.content) }
            .filter { (it.itagItem?.contentLength ?: -1L) > 1L }
            .sortedWith(
                compareByDescending<AudioStream> { it.format == MediaFormat.M4A }
                    .thenByDescending { it.averageBitrate },
            )
            .toList()
        val formatsMs = SystemClock.elapsedRealtime() - formatsStarted
        val validationStarted = SystemClock.elapsedRealtime()
        val selected = candidates.firstOrNull {
            checkCurrent()
            !validate || validateTail(it)
        }
            ?: error("No complete audio stream")
        val validationMs = SystemClock.elapsedRealtime() - validationStarted
        val now = System.currentTimeMillis()
        val expiresAt = calculateExpiry(selected.content, now)
        check(expiresAt > now + EXPIRY_MARGIN_MS)
        val source = CachedSource(
            url = selected.content,
            mimeType = selected.format?.mimeType ?: "audio/mp4",
            expiresAtMillis = expiresAt,
            contentLength = selected.itagItem?.contentLength?.takeIf { it > 1L },
            timings = StageTimings(
                queueMs = startedAt - queuedAt,
                extractorMs = extractorMs,
                formatsMs = formatsMs,
                validationMs = validationMs,
                totalMs = SystemClock.elapsedRealtime() - queuedAt,
            ),
        )
        return store(sourceId, flight, source)
    }

    private fun store(
        sourceId: String,
        flight: CompletableFuture<CachedSource>,
        source: CachedSource,
    ): CachedSource {
        synchronized(flights) {
            check(!closed.get() && !flight.isCancelled) { "Resolution cancelled" }
            check(flights[sourceId] === flight) { "Resolution superseded" }
            cache[sourceId] = source
        }
        saveStore()
        return source
    }

    // One `player` request with the VISIONOS client (~0.1 s). Null means "use NewPipe": the
    // answer was unusable. Three failures in a row pause it for ten minutes, so a changed API
    // costs one slow resolution instead of one per song.
    private fun resolveDirect(
        sourceId: String,
        queuedAt: Long,
        startedAt: Long,
        flight: CompletableFuture<CachedSource>,
        validate: Boolean,
    ): CachedSource? {
        return try {
            val format = vision.resolve(sourceId)
            check(!closed.get() && !flight.isCancelled) { "Resolution cancelled" }
            val usable = isAllowedMediaUrl(format.url) &&
                (!validate || format.contentLength?.let { validateTail(format.url, it, vision.userAgent) } == true)
            if (!usable) throw VisionOsClient.DirectFailure("UNUSABLE", "URL no válida")
            val now = System.currentTimeMillis()
            val expiresAt = calculateExpiry(format.url, now)
            check(expiresAt > now + EXPIRY_MARGIN_MS)
            directFailures = 0
            val elapsed = SystemClock.elapsedRealtime()
            Log.i(LOG_TAG, "device_visionos success=true durationMs=${elapsed - startedAt} itag=${format.itag}")
            store(
                sourceId,
                flight,
                CachedSource(
                    url = format.url,
                    mimeType = format.mimeType,
                    expiresAtMillis = expiresAt,
                    timings = StageTimings(
                        queueMs = startedAt - queuedAt,
                        extractorMs = 0,
                        formatsMs = elapsed - startedAt,
                        validationMs = 0,
                        totalMs = elapsed - queuedAt,
                    ),
                    contentLength = format.contentLength,
                    userAgent = vision.userAgent,
                ),
            )
        } catch (error: Exception) {
            if (closed.get() || flight.isCancelled) throw error
            val failures = ++directFailures
            val code = (error as? VisionOsClient.DirectFailure)?.code ?: error.javaClass.simpleName
            Log.w(LOG_TAG, "device_visionos success=false reason=$code failures=$failures")
            if (failures >= DIRECT_FAILURE_LIMIT) {
                directDisabledUntil = System.currentTimeMillis() + DIRECT_PAUSE_MS
                directFailures = 0
            }
            null
        }
    }

    private fun prefetchHead(id: String) {
        if (flag(PROXY_FLAG)) proxy?.prefetchHead(id)
    }

    // What the proxy needs: the raw source, renewed through NewPipe when the origin rejected it.
    private fun proxySource(id: String, refresh: Boolean): LocalAudioProxy.Source {
        if (refresh) synchronized(flights) { cache.remove(id) }
        val source = resolveSingleFlight(id, validate = refresh, direct = !refresh)
            .get(PROXY_RESOLVE_TIMEOUT_S, TimeUnit.SECONDS)
        return LocalAudioProxy.Source(source.url, source.mimeType, source.contentLength, source.userAgent)
    }

    // Experimental switches live in plain files the settings screen writes (`0`/`1`); on by default.
    private fun flag(name: String): Boolean {
        val file = filesDir?.let { File(it, name) } ?: return true
        return runCatching { !file.exists() || file.readText().trim() != "0" }.getOrDefault(true)
    }

    // Resolved URLs outlive the process (their own `expire` bounds them), so a
    // song played before the app was closed does not pay the extraction again.
    // Runs on the resolver executor.
    private fun loadStore() {
        val file = store ?: return
        runCatching {
            if (!file.exists()) return
            val now = System.currentTimeMillis()
            val rows = JSONArray(file.readText())
            synchronized(flights) {
                for (i in 0 until rows.length()) {
                    val row = rows.optJSONObject(i) ?: continue
                    val id = row.optString("id")
                    val url = row.optString("url")
                    val expiresAt = row.optLong("exp")
                    if (isValidSourceId(id) &&
                        isAllowedMediaUrl(url) &&
                        expiresAt > now + EXPIRY_MARGIN_MS
                    ) {
                        cache[id] = CachedSource(
                            url = url,
                            mimeType = row.optString("mime", "audio/mp4"),
                            expiresAtMillis = expiresAt,
                            contentLength = row.optLong("len", -1L).takeIf { it > 0 },
                            userAgent = row.optString("ua").takeIf { it.isNotEmpty() },
                        )
                    }
                }
            }
        }
    }

    // Runs on the resolver executor, right after a new source is cached.
    private fun saveStore() {
        val file = store ?: return
        runCatching {
            val rows = JSONArray()
            synchronized(flights) {
                for ((id, source) in cache) {
                    rows.put(
                        JSONObject()
                            .put("id", id)
                            .put("url", source.url)
                            .put("mime", source.mimeType)
                            .put("exp", source.expiresAtMillis)
                            .put("len", source.contentLength ?: -1L)
                            .put("ua", source.userAgent.orEmpty()),
                    )
                }
            }
            // Temp file and rename: a crash never leaves half a file behind.
            val temp = File(file.path + ".tmp")
            temp.writeText(rows.toString())
            if (!temp.renameTo(file)) temp.delete()
        }
    }

    private fun initializeExtractor() {
        if (initialized.compareAndSet(false, true)) {
            try {
                NewPipe.init(downloader)
            } catch (error: Throwable) {
                initialized.set(false)
                throw error
            }
        }
    }

    private fun validateTail(stream: AudioStream): Boolean {
        val contentLength = stream.itagItem?.contentLength ?: return false
        return validateTail(stream.content, contentLength, null)
    }

    private fun validateTail(url: String, contentLength: Long, userAgent: String?): Boolean {
        val request = Request.Builder()
            .url(url)
            .header("Range", "bytes=${contentLength - 1}-${contentLength - 1}")
            .header("Accept-Encoding", "identity")
            .apply { userAgent?.let { header("User-Agent", it) } }
            .build()
        return runCatching {
            validationClient.newCall(request).execute().use { response ->
                response.code == 206 &&
                    isAllowedMediaUrl(response.request.url.toString()) &&
                    response.header("Content-Range")?.startsWith(
                        "bytes ${contentLength - 1}-${contentLength - 1}/",
                    ) == true
            }
        }.getOrDefault(false)
    }

    private fun calculateExpiry(value: String, now: Long): Long {
        val providerExpiry = runCatching {
            URI(value).rawQuery
                ?.split('&')
                ?.firstOrNull { it.substringBefore('=') == "expire" }
                ?.substringAfter('=')
                ?.toLong()
                ?.times(1000L)
        }.getOrNull()
        val maximum = now + CACHE_TTL_MS
        return if (providerExpiry == null) {
            maximum
        } else {
            minOf(maximum, providerExpiry - EXPIRY_MARGIN_MS)
        }
    }

    private fun cancelPrefetch() {
        val id = prefetchSourceId
        val flight = prefetchTask
        prefetchTask = null
        prefetchSourceId = null
        if (id == null || flight == null) return
        synchronized(flights) { cancelFlight(id, flight) }
    }

    // Called with the flights lock held; only cancel HTTP for the active flight.
    private fun cancelFlight(sourceId: String, flight: CompletableFuture<CachedSource>) {
        if (!flights.remove(sourceId, flight)) return
        flight.cancel(false)
        if (activeFlight === flight) {
            downloader.cancelActive()
            validationClient.dispatcher.cancelAll()
        }
    }

    private fun cancelAll() {
        prefetchTask = null
        prefetchSourceId = null
        synchronized(flights) {
            for ((id, flight) in flights.toMap()) cancelFlight(id, flight)
            cache.clear()
        }
    }

    private fun timingsMap(value: StageTimings) = mapOf(
        "queueMs" to value.queueMs,
        "extractorMs" to value.extractorMs,
        "formatsMs" to value.formatsMs,
        "validationMs" to value.validationMs,
        "totalMs" to value.totalMs,
    )

    private fun isAllowedMediaUrl(value: String): Boolean = runCatching {
        val uri = URI(value)
        uri.scheme == "https" &&
            (uri.host == "googlevideo.com" || uri.host?.endsWith(".googlevideo.com") == true)
    }.getOrDefault(false)

    private fun isValidSourceId(value: String?): Boolean =
        value != null && SOURCE_ID.matches(value)

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        cancelAll()
        executor.shutdownNow()
        runCatching { proxy?.close() }
        // close() runs on the main thread (Activity.onDestroy). Evicting pooled
        // TLS connections writes to their sockets, which Android forbids there
        // (NetworkOnMainThreadException), so the network teardown gets its own
        // thread.
        Thread(
            {
                runCatching { downloader.close() }
                runCatching {
                    validationClient.dispatcher.executorService.shutdownNow()
                    streamClient.dispatcher.executorService.shutdownNow()
                    validationClient.connectionPool.evictAll()
                }
            },
            "mysic-resolver-close",
        ).start()
    }

    companion object {
        const val CHANNEL = "com.mysic.mysic/device_playback"
        private val SOURCE_ID = Regex("^[A-Za-z0-9_-]{11}$")
        private const val LOG_TAG = "MysicPlayback"
        // Resolved URLs stay valid for hours (their own `expire` still caps
        // each entry), so remembering more of them for longer turns a repeat
        // tap into a cache hit. A URL that stops working mid-life is retried
        // by the player with refresh=true.
        private const val CACHE_LIMIT = 48
        private const val CACHE_TTL_MS = 60 * 60 * 1000L
        private const val WARM_LIMIT = 12
        private const val EXPIRY_MARGIN_MS = 30_000L
        private const val VALIDATION_TIMEOUT_MS = 10_000
        private const val FAST_FLAG = "fast_resolve.txt"
        private const val PROXY_FLAG = "head_proxy.txt"
        private const val DIRECT_FAILURE_LIMIT = 3
        private const val DIRECT_PAUSE_MS = 10 * 60 * 1000L
        private const val BLOCK_PAUSE_MS = 5 * 60 * 1000L
        private const val PROXY_RESOLVE_TIMEOUT_S = 20L
    }
}
