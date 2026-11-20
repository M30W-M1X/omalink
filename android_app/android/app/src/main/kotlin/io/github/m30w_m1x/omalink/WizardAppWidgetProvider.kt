package io.github.m30w_m1x.omalink

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class WizardAppWidgetProvider : AppWidgetProvider() {
    companion object {
        private fun makePending(context: Context, action: String, reqCode: Int): PendingIntent {
            // Target the non-exported WidgetActionReceiver so external apps cannot forge commands
            val intent = Intent(context, WidgetActionReceiver::class.java).apply {
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
                setOnClickPendingIntent(
                    R.id.btn_play,
                    makePending(context, WidgetActionReceiver.ACTION_PLAY, 101),
                )
                setOnClickPendingIntent(
                    R.id.btn_mute,
                    makePending(context, WidgetActionReceiver.ACTION_MUTE, 102),
                )
                setOnClickPendingIntent(
                    R.id.btn_lock,
                    makePending(context, WidgetActionReceiver.ACTION_LOCK, 103),
                )
                setOnClickPendingIntent(
                    R.id.btn_sudo,
                    makePending(context, WidgetActionReceiver.ACTION_SUDO, 104),
                )
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
