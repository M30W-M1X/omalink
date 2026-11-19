package io.github.m30w_m1x.omalink

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class WizardNotificationListenerService : NotificationListenerService() {
    private val executor = Executors.newSingleThreadExecutor()
    private val recentSignatures = ConcurrentHashMap<String, Pair<String, Long>>()

    data class ReplyTarget(
        val pendingIntent: PendingIntent,
        val remoteInput: RemoteInput,
        val createdAt: Long,
    )

    companion object {
        @Volatile
        var onNotificationRelayed: ((Map<String, Any>) -> Unit)? = null

        private val replyTargets = ConcurrentHashMap<String, ReplyTarget>()

        private val CALL_PACKAGE_HINTS = setOf(
            "com.google.android.dialer",
            "com.android.dialer",
            "com.samsung.android.incallui",
            "com.samsung.android.dialer",
            "com.oneplus.dialer",
            "com.android.server.telecom",
        )

        fun sendInlineReply(context: Context, replyId: String, message: String): Boolean {
            val target = replyTargets[replyId] ?: return false
            return try {
                val intent = Intent()
                val bundle = Bundle().apply {
                    putCharSequence(target.remoteInput.resultKey, message)
                }
                RemoteInput.addResultsToIntent(arrayOf(target.remoteInput), intent, bundle)
                target.pendingIntent.send(context, 0, intent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        if (pkg == applicationContext.packageName) return

        val notification = sbn.notification ?: return
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return

        val extras = notification.extras ?: return
        val categoryRaw = notification.category ?: ""
        val isCall = categoryRaw == Notification.CATEGORY_CALL || CALL_PACKAGE_HINTS.contains(pkg)
        val isOngoing = (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0
        if (isOngoing && !isCall) return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim() ?: ""
        val plainText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim() ?: ""
        val body = when {
            bigText.isNotEmpty() -> bigText
            plainText.isNotEmpty() -> plainText
            else -> subText
        }

        if (title.isEmpty() && body.isEmpty()) return

        val now = System.currentTimeMillis()
        val sig = "$title\n$body\n$categoryRaw"
        val prev = recentSignatures[sbn.key]
        if (prev != null && prev.first == sig && (now - prev.second) < 4000L) {
            return
        }
        recentSignatures[sbn.key] = Pair(sig, now)

        val prefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
        val demoMode = (prefs.all["flutter.wizard_demo"] as? Boolean) ?: true
        val relayEnabled = (prefs.all["flutter.wizard_relay_notifications"] as? Boolean) ?: true
        val relayCalls = (prefs.all["flutter.wizard_relay_calls"] as? Boolean) ?: true

        if (demoMode || !relayEnabled) return
        if (isCall && !relayCalls) return

        val host = (prefs.all["flutter.wizard_host"] as? String)?.trim() ?: ""
        val port = (prefs.all["flutter.wizard_port"] as? Number)?.toInt() ?: 7842
        val token = (prefs.all["flutter.wizard_token"] as? String)?.trim() ?: ""
        val useTls = (prefs.all["flutter.wizard_use_tls"] as? Boolean) ?: false
        if (host.isEmpty()) return

        val isMessage = categoryRaw == Notification.CATEGORY_MESSAGE ||
            categoryRaw == Notification.CATEGORY_SOCIAL ||
            extras.containsKey(Notification.EXTRA_MESSAGES)

        val bridgeCategory = when {
            isCall -> "call"
            isMessage -> "message"
            else -> "notification"
        }

        var replyId = ""
        val actions = notification.actions
        if (actions != null) {
            for (action in actions) {
                val inputs = action.remoteInputs
                if (inputs != null && inputs.isNotEmpty() && action.actionIntent != null) {
                    replyId = UUID.randomUUID().toString().substring(0, 10)
                    replyTargets[replyId] = ReplyTarget(action.actionIntent, inputs[0], now)
                    if (replyTargets.size > 30) {
                        val oldest = replyTargets.entries.minByOrNull { it.value.createdAt }?.key
                        if (oldest != null) replyTargets.remove(oldest)
                    }
                    break
                }
            }
        }

        val appLabel = resolveAppName(pkg)

        executor.execute {
            postToBridge(
                host = host,
                port = port,
                token = token,
                useTls = useTls,
                appName = appLabel,
                packageName = pkg,
                category = bridgeCategory,
                title = title,
                body = body,
                caller = if (isCall) title else "",
                replyId = replyId,
            )
        }
    }

    private fun resolveAppName(packageName: String): String {
        return try {
            val pm = applicationContext.packageManager
            val info = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            packageName.substringAfterLast('.')
        } catch (_: Exception) {
            packageName
        }
    }

    private fun postToBridge(
        host: String,
        port: Int,
        token: String,
        useTls: Boolean,
        appName: String,
        packageName: String,
        category: String,
        title: String,
        body: String,
        caller: String,
        replyId: String,
    ) {
        var conn: HttpURLConnection? = null
        try {
            val scheme = if (useTls) "https" else "http"
            val url = URL("$scheme://$host:$port/api/continuity/notify")
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 3500
                readTimeout = 4000
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                if (token.isNotEmpty()) {
                    setRequestProperty("Authorization", "Bearer $token")
                }
            }
            val payload = JSONObject().apply {
                put("app_name", appName)
                put("package_name", packageName)
                put("category", category)
                put("title", title)
                put("body", body)
                if (caller.isNotEmpty()) put("caller", caller)
                if (replyId.isNotEmpty()) {
                    put("can_reply", true)
                    put("reply_id", replyId)
                }
            }
            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(payload.toString())
            }
            val code = conn.responseCode
            if (code in 200..299) {
                onNotificationRelayed?.invoke(
                    mapOf(
                        "event" to "relayed_notification",
                        "app_name" to appName,
                        "package_name" to packageName,
                        "category" to category,
                        "title" to title,
                        "body" to body,
                        "can_reply" to replyId.isNotEmpty(),
                    ),
                )
            }
        } catch (_: Exception) {
            // Best-effort background relay when phone is on LAN/Tailscale
        } finally {
            conn?.disconnect()
        }
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }
}
