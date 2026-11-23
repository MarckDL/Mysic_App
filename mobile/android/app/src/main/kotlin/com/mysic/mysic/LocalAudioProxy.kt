package com.mysic.mysic

import android.os.SystemClock
import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.ThreadFactory
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Servidor HTTP mínimo en `127.0.0.1` que el reproductor usa como si fuera el origen del audio. Es lo
 * que hace el protocolo `mysicstream` del escritorio:
 *
 *  - de las canciones "preparadas" (calentadas o siguientes de la cola) guarda en memoria el primer
 *    tramo (256 KB), así que la petición `bytes=0-` del reproductor se responde **sin tocar la red**;
 *  - el resto lo pide a YouTube en tramos acotados (512 KB hasta el primer MB y luego 2 MB: un
 *    `bytes=X-` abierto lo limita YouTube a ~2× tiempo real) y lo reenvía a medida que llega, con
 *    conexiones reutilizadas (una sola conexión TLS ya abierta para el primer tramo y el resto);
 *  - ante 403/410 renueva la URL una vez y reintenta.
 *
 * Solo escucha en el bucle local y exige un token aleatorio en la ruta: otra app del teléfono no
 * puede pedirle audio. Si algo falla, quien lo usa devuelve la URL directa de siempre.
 */
internal class LocalAudioProxy(
    private val http: OkHttpClient,
    private val sourceFor: (id: String, refresh: Boolean) -> Source,
) : Closeable {
    /** Dónde está el audio: la URL de YouTube y con qué cabecera `User-Agent` hay que pedirlo. */
    class Source(
        val url: String,
        val mimeType: String,
        val contentLength: Long?,
        val userAgent: String?,
    )

    private class Head(val bytes: ByteArray, val total: Long, val at: Long)

    /** La fuente en uso durante una petición (se renueva si YouTube rechaza la URL). */
    private class State(var source: Source, var renewed: Boolean = false)

    private val closed = AtomicBoolean(false)
    private val token: String = ByteArray(16).also { SecureRandom().nextBytes(it) }
        .joinToString("") { "%02x".format(it) }
    private val server = ServerSocket(0, 32, InetAddress.getByName("127.0.0.1"))
    private val daemon = ThreadFactory { runnable ->
        Thread(runnable, "mysic-audio-proxy").apply { isDaemon = true }
    }
    private val workers: ExecutorService = Executors.newCachedThreadPool(daemon)
    private val headWorkers: ExecutorService = Executors.newFixedThreadPool(4, daemon)
    private val heads = LinkedHashMap<String, Head>()
    private val pending = HashMap<String, FutureTask<Head?>>()

    val port: Int get() = server.localPort

    init {
        Thread(::acceptLoop, "mysic-audio-proxy-accept").apply { isDaemon = true }.start()
    }

    /** La dirección que se le da al reproductor en lugar de la de YouTube. */
    fun urlFor(id: String): String = "http://127.0.0.1:$port/a/$token/$id"

    /** Empieza a bajar el primer tramo de [id] (si no lo tiene ya ni va en curso). */
    fun prefetchHead(id: String) {
        if (closed.get()) return
        val task: FutureTask<Head?>
        synchronized(heads) {
            if (heads[id]?.let(::fresh) == true || pending.containsKey(id)) return
            task = FutureTask {
                try {
                    fetchHead(id)
                } finally {
                    synchronized(heads) { pending.remove(id) }
                }
            }
            pending[id] = task
        }
        runCatching { headWorkers.execute(task) }.onFailure {
            synchronized(heads) { pending.remove(id) }
        }
    }

    private fun fresh(head: Head) = SystemClock.elapsedRealtime() - head.at <= HEAD_TTL_MS

    private fun acceptLoop() {
        while (!closed.get()) {
            val socket = try {
                server.accept()
            } catch (_: IOException) {
                return
            }
            runCatching { workers.execute { handle(socket) } }.onFailure { runCatching { socket.close() } }
        }
    }

    // ---- Petición del reproductor ----

    private fun handle(socket: Socket) {
        socket.use { s ->
            runCatching {
                s.soTimeout = 15_000
                s.tcpNoDelay = true
                serve(s.getInputStream(), s.getOutputStream())
            }.onFailure { error ->
                // Lo normal es que el reproductor cierre la conexión (cambio de pista o salto).
                if (error !is IOException) Log.w(TAG, "proxy_error ${error.javaClass.simpleName}")
            }
        }
    }

    private fun serve(input: InputStream, out: OutputStream) {
        val startedAt = SystemClock.elapsedRealtime()
        val lines = readHead(input) ?: return
        val parts = lines.first().split(' ')
        val method = parts.getOrNull(0)
        val path = parts.getOrNull(1).orEmpty().split('/')
        // /a/<token>/<id>
        if ((method != "GET" && method != "HEAD") || path.size != 4 || path[1] != "a" ||
            path[2] != token || !ID.matches(path[3])
        ) {
            status(out, 404, "Not Found")
            return
        }
        val id = path[3]
        val rangeHeader = lines.drop(1)
            .firstOrNull { it.startsWith("range:", ignoreCase = true) }
            ?.substringAfter(':')?.trim()

        val state = try {
            State(sourceFor(id, false))
        } catch (_: Exception) {
            status(out, 502, "Bad Gateway")
            return
        }
        val head = freshHead(id)
        var total = state.source.contentLength ?: head?.total
        if (total == null) total = probeTotal(id, state)
        if (total == null || total <= 0) {
            status(out, 502, "Bad Gateway")
            return
        }
        val range = parseRange(rangeHeader, total)
        if (range == null) {
            val message = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */$total\r\n" +
                "Content-Length: 0\r\nConnection: close\r\n\r\n"
            out.write(message.toByteArray())
            return
        }
        val (start, end) = range
        val partial = rangeHeader != null
        val headers = StringBuilder()
            .append(if (partial) "HTTP/1.1 206 Partial Content\r\n" else "HTTP/1.1 200 OK\r\n")
            .append("Content-Type: ${state.source.mimeType}\r\n")
            .append("Accept-Ranges: bytes\r\n")
            .append("Content-Length: ${end - start + 1}\r\n")
        if (partial) headers.append("Content-Range: bytes $start-$end/$total\r\n")
        headers.append("Connection: close\r\n\r\n")
        out.write(headers.toString().toByteArray())
        if (method == "HEAD") return

        var position = start
        var firstByteLogged = false
        fun logFirstByte(from: String) {
            if (firstByteLogged) return
            firstByteLogged = true
            Log.i(
                TAG,
                "proxy_first_byte id=$id start=$start from=$from " +
                    "ms=${SystemClock.elapsedRealtime() - startedAt}",
            )
        }
        // 1) Lo que ya está en memoria: sin red.
        if (head != null && position < head.bytes.size) {
            val count = (minOf(end + 1, head.bytes.size.toLong()) - position).toInt()
            out.write(head.bytes, position.toInt(), count)
            out.flush()
            logFirstByte("memoria")
            position += count
        }
        // 2) El resto, a YouTube en tramos, reenviado a medida que llega.
        while (position <= end) {
            val length = if (position < RAMP_UNTIL) RAMP_CHUNK else CHUNK
            val chunkEnd = minOf(end, position + length - 1)
            copyRange(id, state, position, chunkEnd, out) { logFirstByte("red") }
            position = chunkEnd + 1
        }
    }

    /** Un tramo `[from, to]` de YouTube, escrito en [out] según llega. */
    private fun copyRange(
        id: String,
        state: State,
        from: Long,
        to: Long,
        out: OutputStream,
        onFirstByte: () -> Unit,
    ) {
        var attempt = 0
        while (true) {
            val request = Request.Builder()
                .url(state.source.url)
                .header("Range", "bytes=$from-$to")
                .header("Accept-Encoding", "identity")
                .apply { state.source.userAgent?.let { header("User-Agent", it) } }
                .build()
            val response = http.newCall(request).execute()
            try {
                val code = response.code
                if ((code == 403 || code == 410) && attempt == 0) {
                    // La URL caducó o se rechazó: se renueva una vez (sin el cliente directo).
                } else {
                    if (code != 206) throw IOException("origen HTTP $code")
                    val body = response.body ?: throw IOException("sin cuerpo")
                    val expected = to - from + 1
                    var sent = 0L
                    val buffer = ByteArray(16 * 1024)
                    body.byteStream().use { stream ->
                        while (true) {
                            val n = stream.read(buffer)
                            if (n < 0) break
                            if (sent == 0L) onFirstByte()
                            out.write(buffer, 0, n)
                            sent += n
                        }
                    }
                    out.flush()
                    if (sent < expected) throw IOException("tramo incompleto")
                    return
                }
            } finally {
                response.close()
            }
            attempt++
            state.source = sourceFor(id, true)
            state.renewed = true
        }
    }

    /** El primer tramo de [id], si está o si se está bajando ahora mismo (se espera un poco). */
    private fun freshHead(id: String): Head? {
        val waiting = synchronized(heads) {
            heads[id]?.takeIf(::fresh)?.let { return it }
            pending[id]
        }
        return runCatching { waiting?.get(2500, TimeUnit.MILLISECONDS) }.getOrNull()
    }

    private fun fetchHead(id: String): Head? = runCatching {
        var source = sourceFor(id, false)
        var attempt = 0
        while (true) {
            val request = Request.Builder()
                .url(source.url)
                .header("Range", "bytes=0-${HEAD_BYTES - 1}")
                .header("Accept-Encoding", "identity")
                .apply { source.userAgent?.let { header("User-Agent", it) } }
                .build()
            http.newCall(request).execute().use { response ->
                val code = response.code
                if ((code == 403 || code == 410) && attempt == 0) return@use
                if (code != 206) return null
                val total = totalFromContentRange(response.header("Content-Range")) ?: source.contentLength
                    ?: return null
                val bytes = response.body?.bytes() ?: return null
                if (bytes.isEmpty()) return null
                val head = Head(bytes, total, SystemClock.elapsedRealtime())
                synchronized(heads) {
                    heads[id] = head
                    while (heads.size > HEAD_MAX) {
                        val oldest = heads.entries.minByOrNull { it.value.at }?.key ?: break
                        heads.remove(oldest)
                    }
                }
                Log.i(TAG, "proxy_head id=$id bytes=${bytes.size}")
                return head
            }
            attempt++
            source = sourceFor(id, true)
        }
        @Suppress("UNREACHABLE_CODE")
        null
    }.getOrNull()

    /** Tamaño total cuando la fuente no lo trae (entradas guardadas de versiones anteriores). */
    private fun probeTotal(id: String, state: State): Long? = runCatching {
        var attempt = 0
        while (true) {
            val request = Request.Builder()
                .url(state.source.url)
                .header("Range", "bytes=0-0")
                .header("Accept-Encoding", "identity")
                .apply { state.source.userAgent?.let { header("User-Agent", it) } }
                .build()
            http.newCall(request).execute().use { response ->
                val code = response.code
                if ((code == 403 || code == 410) && attempt == 0) return@use
                if (code != 206) return null
                return totalFromContentRange(response.header("Content-Range"))
            }
            attempt++
            state.source = sourceFor(id, true)
        }
        @Suppress("UNREACHABLE_CODE")
        null
    }.getOrNull()

    // ---- Utilidades ----

    private fun status(out: OutputStream, code: Int, text: String) {
        out.write("HTTP/1.1 $code $text\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
    }

    /** Cabecera de la petición (hasta la línea vacía), o null si es demasiado grande o se cortó. */
    private fun readHead(input: InputStream): List<String>? {
        val buffer = ByteArrayOutputStream()
        var last = 0
        var count = 0
        while (true) {
            val b = input.read()
            if (b < 0) return null
            buffer.write(b)
            count++
            if (count > MAX_HEAD) return null
            if (last == '\r'.code && b == '\n'.code) {
                val text = buffer.toString(Charsets.ISO_8859_1.name())
                if (text.endsWith("\r\n\r\n")) return text.split("\r\n").filter { it.isNotEmpty() }
            }
            last = b
        }
    }

    companion object {
        private const val TAG = "MysicPlayback"
        private val ID = Regex("^[A-Za-z0-9_-]{11}$")
        private const val HEAD_BYTES = 256 * 1024
        // 24 tramos de 256 KB son 6 MB; viven 15 min (medido: con 3 min, una canción con la URL
        // guardada pero el tramo caducado tardaba ~1 s en sonar).
        private const val HEAD_MAX = 24
        private const val HEAD_TTL_MS = 15 * 60_000L
        private const val RAMP_CHUNK = 512 * 1024L
        private const val RAMP_UNTIL = 1024 * 1024L
        private const val CHUNK = 2 * 1024 * 1024L
        private const val MAX_HEAD = 8 * 1024

        /** `bytes N-M/TOTAL` → TOTAL. */
        internal fun totalFromContentRange(value: String?): Long? =
            value?.substringAfterLast('/')?.trim()?.toLongOrNull()

        /**
         * El tramo `[inicio, fin]` (ambos incluidos) de una cabecera `Range` para un archivo de
         * [total] bytes. Sin cabecera es todo el archivo; null si no es válido (varios rangos, fuera
         * de límites o mal formado).
         */
        internal fun parseRange(header: String?, total: Long): Pair<Long, Long>? {
            if (header.isNullOrBlank()) return 0L to total - 1
            val spec = header.trim().removePrefix("bytes=").takeIf { header.trim().startsWith("bytes=") }
                ?: return null
            if (spec.contains(',')) return null
            val from = spec.substringBefore('-', "")
            val to = spec.substringAfter('-', "")
            if (!spec.contains('-')) return null
            if (from.isEmpty()) {
                val suffix = to.toLongOrNull()?.takeIf { it > 0 } ?: return null
                return maxOf(0L, total - suffix) to total - 1
            }
            val start = from.toLongOrNull() ?: return null
            val end = if (to.isEmpty()) total - 1 else (to.toLongOrNull() ?: return null)
            if (start < 0 || start >= total || end < start) return null
            return start to minOf(end, total - 1)
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        runCatching { server.close() }
        workers.shutdownNow()
        headWorkers.shutdownNow()
        synchronized(heads) {
            heads.clear()
            pending.clear()
        }
    }
}
