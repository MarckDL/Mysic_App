package com.mysic.mysic

import android.os.SystemClock
import android.util.Log
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import okhttp3.Call
import okhttp3.ConnectionPool
import okhttp3.Dispatcher
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

internal class ExtractorDownloader : Downloader(), AutoCloseable {
    private val dispatcher = Dispatcher().apply {
        maxRequests = 2
        maxRequestsPerHost = 2
    }
    private val client = OkHttpClient.Builder()
        .dispatcher(dispatcher)
        .connectionPool(ConnectionPool(2, 5, TimeUnit.MINUTES))
        .connectTimeout(CONNECT_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        .readTimeout(READ_TIMEOUT_MS.toLong(), TimeUnit.MILLISECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()
    private val activeCalls = ConcurrentHashMap.newKeySet<Call>()

    override fun execute(request: Request): Response {
        val uri = URI(request.url())
        if (uri.scheme != "https") {
            throw IOException("Only HTTPS requests are allowed")
        }
        val builder = okhttp3.Request.Builder().url(request.url())
        if (request.headers().keys.none { it.equals("User-Agent", ignoreCase = true) }) {
            builder.header("User-Agent", DEFAULT_USER_AGENT)
        }
        request.headers().forEach { (name, values) ->
            if (!name.equals("Accept-Encoding", ignoreCase = true)) {
                values.forEach { value -> builder.addHeader(name, value) }
            }
        }
        val body = request.dataToSend()?.toRequestBody(
            request.headers()["Content-Type"]?.firstOrNull()?.toMediaTypeOrNull(),
        )
        builder.method(request.httpMethod(), body)
        val call = client.newCall(builder.build())
        activeCalls.add(call)
        val startedAt = SystemClock.elapsedRealtime()
        try {
            return call.execute().use { response ->
                if (response.request.url.scheme != "https") {
                    throw IOException("Redirected outside HTTPS")
                }
                val responseBody = if (request.httpMethod() == "HEAD") "" else {
                    response.body?.byteStream()?.use {
                        String(readLimited(it), Charsets.UTF_8)
                    }.orEmpty()
                }
                Log.i(
                    LOG_TAG,
                    "extractor_http success=true durationMs=" +
                        (SystemClock.elapsedRealtime() - startedAt) +
                        " statusGroup=${response.code / 100}xx",
                )
                Response(
                    response.code,
                    response.message,
                    response.headers.toMultimap(),
                    responseBody,
                    response.request.url.toString(),
                )
            }
        } catch (error: IOException) {
            Log.w(
                LOG_TAG,
                "extractor_http success=false durationMs=" +
                    (SystemClock.elapsedRealtime() - startedAt) +
                    " reason=${error.javaClass.simpleName}",
            )
            throw error
        } finally {
            activeCalls.remove(call)
        }
    }

    fun cancelActive() = activeCalls.forEach(Call::cancel)

    override fun close() {
        cancelActive()
        dispatcher.executorService.shutdownNow()
        client.connectionPool.evictAll()
    }

    private fun readLimited(stream: InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        var total = 0
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            total += count
            if (total > MAX_RESPONSE_BYTES) {
                throw IOException("Extractor response exceeded limit")
            }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 12_000
        const val READ_TIMEOUT_MS = 20_000
        const val MAX_RESPONSE_BYTES = 4 * 1024 * 1024
        const val DEFAULT_USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) " +
                "Gecko/20100101 Firefox/140.0"
        const val LOG_TAG = "MysicPlayback"
    }
}
