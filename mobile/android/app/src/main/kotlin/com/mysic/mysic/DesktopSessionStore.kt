package com.mysic.mysic

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Only the session issued to this installation by Mysic desktop is stored here. */
internal class DesktopSessionStore(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.mysic/desktop_session"
        private const val KEY_ALIAS = "mysic.original.session.v1"
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val uid = call.argument<String>("uid")
        if (uid.isNullOrBlank() || uid.length > 128) {
            result.error("INVALID_ACCOUNT", "Cuenta inválida", null)
            return
        }
        val owner = uid.toByteArray(Charsets.UTF_8)
        val name = MessageDigest.getInstance("SHA-256").digest(owner).joinToString("") { "%02x".format(it) }
        val file = AtomicFile(File(context.noBackupFilesDir, "desktop-$name"))
        try {
            when (call.method) {
                "read" -> {
                    val bytes = try { file.readFully() } catch (_: java.io.FileNotFoundException) { null }
                    val value = bytes?.let {
                        if (it.size !in 29..16384) throw IllegalArgumentException()
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, it, 0, 12))
                        cipher.updateAAD(owner)
                        String(cipher.doFinal(it, 12, it.size - 12), Charsets.UTF_8)
                    }
                    result.success(value)
                }
                "write" -> {
                    val value = call.argument<String>("value")
                    if (value == null) {
                        file.delete()
                    } else {
                        require(value.length <= 8192)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.ENCRYPT_MODE, key())
                        cipher.updateAAD(owner)
                        val bytes = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
                        val output = file.startWrite()
                        try { output.write(bytes); file.finishWrite(output) }
                        catch (error: Exception) { file.failWrite(output); throw error }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("DESKTOP_STORAGE", "No se pudo acceder a la sesión de este dispositivo", null)
        }
    }
}
