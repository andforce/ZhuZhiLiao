package com.azhegezhege.zhuzhiliao.network

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class PlayerIdentityStore(context: Context) {
    private val preferences = context.getSharedPreferences("zzl_identity", Context.MODE_PRIVATE)
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun load(): PlayerIdentity? = runCatching {
        val encrypted = Base64.decode(preferences.getString(KEY_VALUE, null) ?: return null, Base64.NO_WRAP)
        val iv = Base64.decode(preferences.getString(KEY_IV, null) ?: return null, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
        val json = JSONObject(String(cipher.doFinal(encrypted), Charsets.UTF_8))
        PlayerIdentity(json.getString("id"), json.getString("code"), json.getString("token"))
    }.getOrNull()

    fun save(identity: PlayerIdentity) {
        val text = JSONObject()
            .put("id", identity.id)
            .put("code", identity.code)
            .put("token", identity.token)
            .toString()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        preferences.edit()
            .putString(KEY_VALUE, Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putString(KEY_IV, Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .apply()
    }

    fun delete() {
        preferences.edit().clear().apply()
        if (keyStore.containsAlias(KEY_ALIAS)) keyStore.deleteEntry(KEY_ALIAS)
    }

    private fun secretKey(): SecretKey {
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    companion object {
        private const val KEY_ALIAS = "com.azhegezhege.zhuzhiliao.player"
        private const val KEY_VALUE = "identity_value"
        private const val KEY_IV = "identity_iv"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
