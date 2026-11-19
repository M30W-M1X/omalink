package com.omarchy.omalink

import android.content.Context
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

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
        fun sendBridgeAction(context: Context, action: String, params: Map<String, Any>): Boolean {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val demo = (prefs.all["flutter.wizard_demo"] as? Boolean) ?: true
            if (demo) return false
            val host = (prefs.all["flutter.wizard_host"] as? String)?.trim() ?: ""
            val port = (prefs.all["flutter.wizard_port"] as? Number)?.toInt() ?: 7842
            val token = (prefs.all["flutter.wizard_token"] as? String)?.trim() ?: ""
            val useTls = (prefs.all["flutter.wizard_use_tls"] as? Boolean) ?: false
            if (host.isEmpty()) return false

            var conn: HttpURLConnection? = null
            return try {
                val scheme = if (useTls) "https" else "http"
                conn = (URL("$scheme://$host:$port/api/system/action").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 3500
                    readTimeout = 4500
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    if (token.isNotEmpty()) {
                        setRequestProperty("Authorization", "Bearer $token")
                    }
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
