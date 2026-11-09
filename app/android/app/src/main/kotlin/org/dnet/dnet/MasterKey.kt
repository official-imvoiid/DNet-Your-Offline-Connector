package org.dnet.dnet

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps the key that unlocks the vault.
 *
 * The master key is 32 random bytes. It is never written to disk as it is.
 * It is encrypted with AES-256-GCM under a wrapping key that lives in the
 * Android Keystore and cannot be read out of it, and only that encrypted
 * form is stored. Copying the app's files to another phone is therefore not
 * enough to open them.
 *
 * Not yet verified on devices.
 */
class MasterKey(private val dir: File) {
    private val file = File(dir, "master.key")

    /** Returns the master key as 64 hex digits, making it on first use. */
    fun loadOrCreate(fresh: Boolean): String {
        if (fresh) destroy()
        val key = if (file.exists()) unwrap(file.readBytes()) else create()
        try {
            return key.joinToString("") { "%02x".format(it) }
        } finally {
            key.fill(0)
        }
    }

    private fun create(): ByteArray {
        val key = ByteArray(KEY_BYTES).also { SecureRandom().nextBytes(it) }
        dir.mkdirs()
        // Written under another name and renamed, so a crash cannot leave
        // half a key behind.
        val temporary = File(dir, "master.key.new")
        temporary.writeBytes(wrap(key))
        if (!temporary.renameTo(file)) {
            temporary.delete()
            throw IllegalStateException("could not save the wrapped key")
        }
        return key
    }

    private fun destroy() {
        file.delete()
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        if (store.containsAlias(ALIAS)) store.deleteEntry(ALIAS)
    }

    private fun wrappingKey(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
            .apply { init(spec) }
            .generateKey()
    }

    /** Returns the nonce followed by the ciphertext. */
    private fun wrap(key: ByteArray): ByteArray {
        // The Keystore picks a fresh random nonce for each encryption.
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey())
        return cipher.iv + cipher.doFinal(key)
    }

    private fun unwrap(wrapped: ByteArray): ByteArray {
        require(wrapped.size > NONCE_BYTES) { "the stored key is too short" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            wrappingKey(),
            GCMParameterSpec(TAG_BITS, wrapped, 0, NONCE_BYTES),
        )
        val key = cipher.doFinal(wrapped, NONCE_BYTES, wrapped.size - NONCE_BYTES)
        check(key.size == KEY_BYTES) { "the stored key has the wrong length" }
        return key
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "dnet_master_wrap_v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val KEY_BYTES = 32
        const val NONCE_BYTES = 12
        const val TAG_BITS = 128
    }
}
