package com.mysic.mysic

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * La cookie de YouTube Music, cifrada con una clave del Keystore de Android que no sale del
 * dispositivo. Un archivo copiado a otro teléfono no se puede leer.
 */
class YtmSessionStore(context: Context) {
    private val file = File(context.filesDir, "ytm_session.bin")

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    @Synchronized
    fun save(cookie: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        file.writeBytes(cipher.iv + cipher.doFinal(cookie.toByteArray(Charsets.UTF_8)))
    }

    @Synchronized
    fun load(): String? = try {
        if (!file.exists()) {
            null
        } else {
            val bytes = file.readBytes()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, IV_SIZE))
            String(cipher.doFinal(bytes, IV_SIZE, bytes.size - IV_SIZE), Charsets.UTF_8)
        }
    } catch (_: Exception) {
        // Clave perdida o archivo dañado: se pide iniciar sesión otra vez.
        file.delete()
        null
    }

    @Synchronized
    fun clear() {
        file.delete()
    }

    private companion object {
        const val ALIAS = "mysic_ytm_session"
        const val IV_SIZE = 12
    }
}
