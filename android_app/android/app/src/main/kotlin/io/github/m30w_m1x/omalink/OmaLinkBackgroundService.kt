package io.github.m30w_m1x.omalink

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Persistent foreground service that keeps the OmaLink Dart isolate, WebSocket link,
 * Continuity notification relay, and live AI agent session alerts alive in the background.
 *
 * Uses the exact same silent channel (`omalink_vitals`) and notification ID (`4243`) as
 * Flutter's Vitals & Agy Limits shade card so only a single silent notification appears.
 */
class OmaLinkBackgroundService : Service() {
    companion object {
        const val CHANNEL_ID = "omalink_vitals"
        const val CHANNEL_NAME = "OmaLink Vitals & Agy Limits"
        const val NOTIFICATION_ID = 4243
        const val ACTION_START = "io.github.m30w_m1x.omalink.ACTION_BG_START"
        const val ACTION_STOP = "io.github.m30w_m1x.omalink.ACTION_BG_STOP"
        const val EXTRA_SUBTITLE = "subtitle"

        fun start(context: Context, subtitle: String? = null) {
            val intent = Intent(context, OmaLinkBackgroundService::class.java).apply {
                action = ACTION_START
                if (!subtitle.isNullOrBlank()) {
                    putExtra(EXTRA_SUBTITLE, subtitle)
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, OmaLinkBackgroundService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.stopService(intent)
            } catch (_: Exception) {}
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        ensureSilentChannel()
        val subtitle = intent?.getStringExtra(EXTRA_SUBTITLE)
            ?.takeIf { it.isNotBlank() }
            ?: "Connected to Omarchy • Listening for agent alerts & Continuity"

        val notification = buildNotification(subtitle)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    private fun ensureSilentChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Silent ongoing connection & live Omarchy vitals / Agy limits card."
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        mgr.createNotificationChannel(channel)
    }

    private fun buildNotification(subtitle: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            this,
            4243,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.drawable.ic_wizard_notify)
            .setContentTitle("OmaLink • Background Link Active")
            .setContentText(subtitle)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pi)
            .build()
    }
}
