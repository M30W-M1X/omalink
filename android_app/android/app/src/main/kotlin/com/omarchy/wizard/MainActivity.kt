package com.omarchy.wizard

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.omarchy.wizard/continuity"
        private const val EVENT_CHANNEL = "com.omarchy.wizard/continuity_events"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var pendingShare: Map<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent, emitLive = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent, emitLive = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isNotificationListenerEnabled" -> {
                        result.success(isNotificationServiceEnabled())
                    }
                    "openNotificationListenerSettings" -> {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "consumePendingShare" -> {
                        val payload = pendingShare
                        pendingShare = null
                        result.success(payload)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                        WizardNotificationListenerService.onNotificationRelayed = { payload ->
                            mainHandler.post {
                                eventSink?.success(payload)
                            }
                        }
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                        WizardNotificationListenerService.onNotificationRelayed = null
                    }
                },
            )
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val cn = ComponentName(this, WizardNotificationListenerService::class.java)
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?: return false
        return flat.split(':').any { entry ->
            entry == cn.flattenToString() || entry == cn.flattenToShortString()
        }
    }

    private fun handleIncomingIntent(intent: Intent?, emitLive: Boolean) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND) return
        val mime = intent.type ?: ""
        if (!mime.startsWith("text/")) return

        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim() ?: ""
        val sharedSubject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim() ?: ""
        if (sharedText.isEmpty()) return

        val callerPkg = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            referrer?.host ?: ""
        } else {
            ""
        }

        val payload = mapOf(
            "event" to "share",
            "text" to sharedText,
            "subject" to sharedSubject,
            "packageName" to callerPkg,
        )

        if (emitLive && eventSink != null) {
            mainHandler.post {
                eventSink?.success(payload)
            }
        } else {
            pendingShare = mapOf(
                "text" to sharedText,
                "subject" to sharedSubject,
                "packageName" to callerPkg,
            )
        }
    }
}
