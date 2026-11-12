package com.mysic.mysic

import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

internal class ExtractorDownloader : Downloader() {
    override fun execute(request: Request): Response {
        val uri = URI(request.url())
        if (uri.scheme != "https") {
            throw IOException("Only HTTPS requests are allowed")
        }
        val connection = URL(request.url()).openConnection() as HttpURLConnection
        try {
            connection.instanceFollowRedirects = true
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.requestMethod = request.httpMethod()
            connection.setRequestProperty("Accept-Encoding", "identity")
            request.headers().forEach { (name, values) ->
                values.forEach { value -> connection.addRequestProperty(name, value) }
            }
            request.dataToSend()?.let { body ->
                connection.doOutput = true
                connection.outputStream.use { it.write(body) }
            }

            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val responseBody = if (request.httpMethod() == "HEAD" || stream == null) {
                ""
            } else {
                stream.use { String(readLimited(it), Charsets.UTF_8) }
            }
            val headers = connection.headerFields
                .filterKeys { it != null }
                .mapKeys { it.key!! }
                .mapValues { it.value.filterNotNull() }
            return Response(
                status,
                connection.responseMessage.orEmpty(),
                headers,
                responseBody,
                connection.url.toString(),
            )
        } finally {
            connection.disconnect()
        }
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
    }
}
