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
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import java.io.Closeable
import java.net.URI
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

internal class DevicePlaybackResolver : MethodChannel.MethodCallHandler, Closeable {
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
    )

    private val initialized = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val generation = AtomicInteger()
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val downloader = ExtractorDownloader()
    private val validationClient = OkHttpClient.Builder()
        .connectTimeout(VALIDATION_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        .readTimeout(VALIDATION_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()
    private val cache = object : LinkedHashMap<String, CachedSource>(CACHE_LIMIT, 0.75f, true) {
        override fun removeEldestEntry(
            eldest: MutableMap.MutableEntry<String, CachedSource>?,
        ): Boolean = size > CACHE_LIMIT
    }
    private val flights = mutableMapOf<String, CompletableFuture<CachedSource>>()
    private var prefetchSourceId: String? = null
    private var prefetchTask: Future<*>? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "warmUp" -> {
                executor.execute {
                    runCatching { initializeExtractor() }
                    mainHandler.post { result.success(null) }
                }
            }
            "resolve" -> resolveCall(call, result)
            "prefetch" -> prefetchCall(call, result)
            "cancelPrefetch" -> {
                cancelPrefetch()
                result.success(null)
            }
            "clear" -> {
                cancelAll()
                synchronized(cache) { cache.clear() }
                synchronized(flights) { flights.clear() }
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
        if (prefetchSourceId != sourceId) cancelPrefetch()
        val startedAt = SystemClock.elapsedRealtime()
        resolveSingleFlight(sourceId!!).whenComplete { source, error ->
            val duration = SystemClock.elapsedRealtime() - startedAt
            if (error == null && source != null) {
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
                            "url" to source.url,
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
                mainHandler.post {
                    result.error(
                        "RESOLUTION_FAILED",
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
        prefetchSourceId = sourceId
        val completion = resolveSingleFlight(sourceId!!)
        prefetchTask = completion.whenComplete { _, _ ->
            if (prefetchSourceId == sourceId) {
                prefetchSourceId = null
                prefetchTask = null
            }
            mainHandler.post { result.success(null) }
        }
    }

    private fun resolveSingleFlight(sourceId: String): CompletableFuture<CachedSource> {
        cached(sourceId)?.let { return CompletableFuture.completedFuture(it) }
        synchronized(flights) {
            flights[sourceId]?.let { return it }
            val queuedAt = SystemClock.elapsedRealtime()
            val requestedGeneration = generation.get()
            val future = CompletableFuture<CachedSource>()
            flights[sourceId] = future
            executor.execute {
                try {
                    future.complete(
                        resolveUncached(sourceId, queuedAt, requestedGeneration),
                    )
                } catch (error: Throwable) {
                    future.completeExceptionally(error)
                } finally {
                    synchronized(flights) { flights.remove(sourceId, future) }
                }
            }
            return future
        }
    }

    private fun cached(sourceId: String): CachedSource? {
        val now = System.currentTimeMillis()
        synchronized(cache) {
            val source = cache[sourceId]
            if (source != null && source.expiresAtMillis > now + EXPIRY_MARGIN_MS) {
                return source.copy(cacheHit = true, timings = null)
            }
            cache.remove(sourceId)
        }
        return null
    }

    private fun resolveUncached(
        sourceId: String,
        queuedAt: Long,
        requestedGeneration: Int,
    ): CachedSource {
        check(!closed.get())
        val startedAt = SystemClock.elapsedRealtime()
        initializeExtractor()
        val extractorStarted = SystemClock.elapsedRealtime()
        val extractor = ServiceList.YouTube.getStreamExtractor(
            "https://www.youtube.com/watch?v=$sourceId",
        )
        extractor.fetchPage()
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
        val selected = candidates.firstOrNull { validateTail(it) }
            ?: error("No complete audio stream")
        val validationMs = SystemClock.elapsedRealtime() - validationStarted
        val now = System.currentTimeMillis()
        val expiresAt = calculateExpiry(selected.content, now)
        check(expiresAt > now + EXPIRY_MARGIN_MS)
        check(generation.get() == requestedGeneration) { "Resolution cancelled" }
        val source = CachedSource(
            url = selected.content,
            mimeType = selected.format?.mimeType ?: "audio/mp4",
            expiresAtMillis = expiresAt,
            timings = StageTimings(
                queueMs = startedAt - queuedAt,
                extractorMs = extractorMs,
                formatsMs = formatsMs,
                validationMs = validationMs,
                totalMs = SystemClock.elapsedRealtime() - queuedAt,
            ),
        )
        synchronized(cache) { cache[sourceId] = source }
        return source
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
        val request = Request.Builder()
            .url(stream.content)
            .header("Range", "bytes=${contentLength - 1}-${contentLength - 1}")
            .header("Accept-Encoding", "identity")
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
        if (prefetchSourceId == null) return
        generation.incrementAndGet()
        prefetchTask?.cancel(true)
        prefetchTask = null
        prefetchSourceId = null
        downloader.cancelActive()
    }

    private fun cancelAll() {
        generation.incrementAndGet()
        prefetchTask?.cancel(true)
        prefetchTask = null
        prefetchSourceId = null
        downloader.cancelActive()
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
        synchronized(cache) { cache.clear() }
        synchronized(flights) { flights.clear() }
        downloader.close()
        validationClient.dispatcher.executorService.shutdownNow()
        validationClient.connectionPool.evictAll()
        executor.shutdownNow()
    }

    companion object {
        const val CHANNEL = "com.mysic.mysic/device_playback"
        private val SOURCE_ID = Regex("^[A-Za-z0-9_-]{11}$")
        private const val LOG_TAG = "MysicPlayback"
        private const val CACHE_LIMIT = 3
        private const val CACHE_TTL_MS = 4 * 60 * 1000L
        private const val EXPIRY_MARGIN_MS = 30_000L
        private const val VALIDATION_TIMEOUT_MS = 10_000
    }
}
