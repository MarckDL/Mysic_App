package com.mysic.mysic

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.schabi.newpipe.extractor.MediaFormat
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import java.io.Closeable
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal class DevicePlaybackResolver : MethodChannel.MethodCallHandler, Closeable {
    private data class CachedSource(
        val url: String,
        val mimeType: String,
        val expiresAtMillis: Long,
    )

    private val initialized = AtomicBoolean(false)
    // Una sola extracción evita picos de CPU/RAM si el usuario cambia de pista
    // mientras se está preparando la siguiente.
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val cache = object : LinkedHashMap<String, CachedSource>(CACHE_LIMIT, 0.75f, true) {
        override fun removeEldestEntry(
            eldest: MutableMap.MutableEntry<String, CachedSource>?,
        ): Boolean = size > CACHE_LIMIT
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "resolve" -> {
                val sourceId = call.argument<String>("sourceId")
                if (!isValidSourceId(sourceId)) {
                    result.error("INVALID_SOURCE", "Invalid source id", null)
                    return
                }
                executor.execute {
                    val startedAt = SystemClock.elapsedRealtime()
                    try {
                        val source = resolve(sourceId!!)
                        Log.i(
                            LOG_TAG,
                            "device_resolution success=true durationMs=" +
                                (SystemClock.elapsedRealtime() - startedAt),
                        )
                        mainHandler.post {
                            result.success(
                                mapOf(
                                    "url" to source.url,
                                    "mimeType" to source.mimeType,
                                ),
                            )
                        }
                    } catch (error: Throwable) {
                        Log.w(
                            LOG_TAG,
                            "device_resolution success=false durationMs=" +
                                (SystemClock.elapsedRealtime() - startedAt) +
                                " reason=${error.javaClass.simpleName}",
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
            "prefetch" -> {
                val sourceId = call.argument<String>("sourceId")
                if (!isValidSourceId(sourceId)) {
                    result.success(null)
                    return
                }
                executor.execute {
                    runCatching { resolve(sourceId!!) }
                    mainHandler.post { result.success(null) }
                }
            }
            "clear" -> {
                synchronized(cache) { cache.clear() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun resolve(sourceId: String): CachedSource {
        val now = System.currentTimeMillis()
        synchronized(cache) {
            cache[sourceId]?.takeIf { it.expiresAtMillis > now }?.let { return it }
            cache.remove(sourceId)
        }
        initializeExtractor()
        val info = StreamInfo.getInfo(
            ServiceList.YouTube,
            "https://www.youtube.com/watch?v=$sourceId",
        )
        val selected = info.audioStreams
            .asSequence()
            .filter { it.isUrl }
            .filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }
            .filter { isAllowedMediaUrl(it.content) }
            .sortedWith(
                compareByDescending<AudioStream> { it.format == MediaFormat.M4A }
                    .thenByDescending { it.averageBitrate },
            )
            .firstOrNull { validateTail(it) }
            ?: error("No complete audio stream")
        val mimeType = selected.format?.mimeType ?: "audio/mp4"
        return CachedSource(
            url = selected.content,
            mimeType = mimeType,
            expiresAtMillis = now + CACHE_TTL_MS,
        ).also { source -> synchronized(cache) { cache[sourceId] = source } }
    }

    private fun initializeExtractor() {
        if (initialized.compareAndSet(false, true)) {
            try {
                NewPipe.init(ExtractorDownloader())
            } catch (error: Throwable) {
                initialized.set(false)
                throw error
            }
        }
    }

    private fun validateTail(stream: AudioStream): Boolean {
        val contentLength = stream.itagItem?.contentLength ?: return false
        if (contentLength <= 1L) return false
        val connection = URL(stream.content).openConnection() as HttpURLConnection
        return try {
            connection.instanceFollowRedirects = true
            connection.connectTimeout = VALIDATION_TIMEOUT_MS
            connection.readTimeout = VALIDATION_TIMEOUT_MS
            connection.setRequestProperty(
                "Range",
                "bytes=${contentLength - 1}-${contentLength - 1}",
            )
            connection.setRequestProperty("Accept-Encoding", "identity")
            connection.responseCode == HttpURLConnection.HTTP_PARTIAL
        } finally {
            connection.disconnect()
        }
    }

    private fun isAllowedMediaUrl(value: String): Boolean = runCatching {
        val uri = URI(value)
        uri.scheme == "https" &&
            (uri.host == "googlevideo.com" || uri.host?.endsWith(".googlevideo.com") == true)
    }.getOrDefault(false)

    private fun isValidSourceId(value: String?): Boolean =
        value != null && SOURCE_ID.matches(value)

    override fun close() {
        synchronized(cache) { cache.clear() }
        executor.shutdownNow()
    }

    companion object {
        const val CHANNEL = "com.mysic.mysic/device_playback"
        private val SOURCE_ID = Regex("^[A-Za-z0-9_-]{11}$")
        private const val LOG_TAG = "MysicPlayback"
        private const val CACHE_LIMIT = 3
        private const val CACHE_TTL_MS = 4 * 60 * 1000L
        private const val VALIDATION_TIMEOUT_MS = 10_000
    }
}
