package io.github.m30w_m1x.omalink

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.concurrent.Executors

/**
 * Non-exported receiver (android:exported="false") that executes Home Screen Widget
 * actions. Keeping this receiver private prevents unrelated Android apps from spoofing
 * widget broadcasts to trigger Lock, Mute, Play, or Sudo commands.
 */
class WidgetActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_PLAY = "io.github.m30w_m1x.omalink.WIDGET_PLAY"
        const val ACTION_MUTE = "io.github.m30w_m1x.omalink.WIDGET_MUTE"
        const val ACTION_LOCK = "io.github.m30w_m1x.omalink.WIDGET_LOCK"
        const val ACTION_SUDO = "io.github.m30w_m1x.omalink.WIDGET_SUDO"
        private val executor = Executors.newSingleThreadExecutor()
    }

    override fun onReceive(context: Context, intent: Intent) {
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
