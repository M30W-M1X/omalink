package io.github.m30w_m1x.omalink

import android.content.Context
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.Executors
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

class WizardQuickTileService : TileService() {
    private val executor = Executors.newSingleThreadExecutor()

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            label = "Lock Omarchy"
            state = Tile.STATE_INACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        qsTile?.apply {
            state = Tile.STATE_ACTIVE
            updateTile()
        }
        executor.execute {
            sendBridgeAction(applicationContext, "system.lock", emptyMap())
            qsTile?.apply {
                state = Tile.STATE_INACTIVE
                updateTile()
            }
        }
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private fun sha256Hex(bytes: ByteArray): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
            return digest.joinToString("") { "%02x".format(it) }
        }

        private fun buildPinnedSslContext(expectedSha256: String): SSLContext {
            val expected = expectedSha256.trim().lowercase()
            val trustManager = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                    throw CertificateException("Client auth not supported")
                }

                override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                    if (expected.length != 64 || chain.isNullOrEmpty()) {
                        throw CertificateException("Missing pinned SHA-256 fingerprint")
                    }
                    val actual = sha256Hex(chain[0].encoded)
                    if (!MessageDigest.isEqual(actual.toByteArray(), expected.toByteArray())) {
                        throw CertificateException("Pinned TLS certificate mismatch")
                    }
                }

                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            }
            return SSLContext.getInstance("TLS").apply {
                init(null, arrayOf(trustManager), null)
            }
        }

        fun sendBridgeAction(context: Context, action: String, params: Map<String, Any>): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val demo = (prefs.all["flutter.wizard_demo"] as? Boolean) ?: true
            if (demo) return false
            val host = (prefs.all["flutter.wizard_host"] as? String)?.trim() ?: ""
            val port = (prefs.all["flutter.wizard_port"] as? Number)?.toInt() ?: 7842
            val token = (prefs.all["flutter.wizard_token"] as? String)?.trim() ?: ""
            val useTls = (prefs.all["flutter.wizard_use_tls"] as? Boolean) ?: true
            val tlsFp = (prefs.all["flutter.wizard_tls_fingerprint"] as? String)?.trim() ?: ""
            if (host.isEmpty() || token.isEmpty()) return false

            var conn: HttpURLConnection? = null
            return try {
                val scheme = if (useTls) "https" else "http"
                conn = (URL("$scheme://$host:$port/api/system/action").openConnection() as HttpURLConnection).apply {
                    if (this is HttpsURLConnection && tlsFp.length == 64) {
                        sslSocketFactory = buildPinnedSslContext(tlsFp).socketFactory
                        setHostnameVerifier { hostname, _ -> hostname == host }
                    }
                    requestMethod = "POST"
                    connectTimeout = 3500
                    readTimeout = 4500
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    setRequestProperty("Authorization", "Bearer $token")
                }
                val body = JSONObject().apply {
                    put("action", action)
                    if (params.isNotEmpty()) put("params", JSONObject(params))
                }
                OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(body.toString()) }
                conn.responseCode in 200..299
            } catch (_: Exception) {
                false
            } finally {
                conn?.disconnect()
            }
        }
    }
}
