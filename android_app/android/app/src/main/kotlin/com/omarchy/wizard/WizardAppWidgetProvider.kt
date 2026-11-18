package com.omarchy.wizard

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.util.concurrent.Executors

class WizardAppWidgetProvider : AppWidgetProvider() {
    companion object {
        private const val ACTION_PLAY = "com.omarchy.wizard.WIDGET_PLAY"
        private const val ACTION_MUTE = "com.omarchy.wizard.WIDGET_MUTE"
        private const val ACTION_LOCK = "com.omarchy.wizard.WIDGET_LOCK"
        private const val ACTION_SUDO = "com.omarchy.wizard.WIDGET_SUDO"
        private val executor = Executors.newSingleThreadExecutor()

        private fun makePending(context: Context, action: String, reqCode: Int): PendingIntent {
            val intent = Intent(context, WizardAppWidgetProvider::class.java).apply {
                this.action = action
            }
            return PendingIntent.getBroadcast(
                context,
                reqCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.wizard_widget).apply {
                setOnClickPendingIntent(R.id.btn_play, makePending(context, ACTION_PLAY, 101))
                setOnClickPendingIntent(R.id.btn_mute, makePending(context, ACTION_MUTE, 102))
                setOnClickPendingIntent(R.id.btn_lock, makePending(context, ACTION_LOCK, 103))
                setOnClickPendingIntent(R.id.btn_sudo, makePending(context, ACTION_SUDO, 104))
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_PLAY -> executor.execute {
                WizardQuickTileService.sendBridgeAction(context, "media.play_pause", emptyMap())
            }
            ACTION_MUTE -> executor.execute {
                WizardQuickTileService.sendBridgeAction(context, "audio.toggle_mute", emptyMap())
            }
            ACTION_LOCK -> executor.execute {
                WizardQuickTileService.sendBridgeAction(context, "system.lock", emptyMap())
            }
            ACTION_SUDO -> executor.execute {
                WizardQuickTileService.sendBridgeAction(
                    context,
                    "security.sudo_prompt",
                    mapOf("duration" to "15"),
                )
            }
        }
    }
}
