package com.omarchy.wizard

import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.omarchy.wizard/continuity"
        private const val EVENT_CHANNEL = "com.omarchy.wizard/continuity_events"
        private const val MAX_SHARE_BYTES = 25 * 1024 * 1024
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var eventSink: EventChannel.EventSink? = null
    private var pendingShare: Map<String, Any>? = null
    private var pendingPairUri: String? = null
    private var mediaPlayer: MediaPlayer? = null
    private var stopRingRunnable: Runnable? = null

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
                    "consumePendingPairUri" -> {
                        val uri = pendingPairUri
                        pendingPairUri = null
                        result.success(uri)
                    }
                    "replyToNotification" -> {
                        val replyId = call.argument<String>("replyId") ?: ""
                        val text = call.argument<String>("text") ?: ""
                        val ok = WizardNotificationListenerService.sendInlineReply(
                            applicationContext,
                            replyId,
                            text,
                        )
                        result.success(ok)
                    }
                    "getDeviceStatus" -> {
                        result.success(readBatteryStatus())
                    }
                    "ringPhone" -> {
                        val duration = call.argument<Int>("duration") ?: 12
                        startRinging(duration)
                        result.success(true)
                    }
                    "stopRinging" -> {
                        stopRinging()
                        result.success(true)
                    }
                    "discoverBridges" -> {
                        discoverMdnsBridges { found ->
                            mainHandler.post { result.success(found) }
                        }
                    }
                    "saveToDownloads" -> {
                        val filename = call.argument<String>("filename") ?: "download.bin"
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.success(null)
                        } else {
                            ioExecutor.execute {
                                val savedPath = saveBytesToDownloads(filename, bytes)
                                mainHandler.post { result.success(savedPath) }
                            }
                        }
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

    private fun readBatteryStatus(): Map<String, Any> {
        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val pct = if (level >= 0 && scale > 0) (level * 100) / scale else -1
        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        return mapOf(
            "name" to (Build.MODEL ?: "Android"),
            "battery" to pct,
            "charging" to charging,
        )
    }

    private fun startRinging(durationSec: Int) {
        stopRinging()
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(applicationContext, uri)
                isLooping = true
                prepare()
                start()
            }
            mediaPlayer = player
            val r = Runnable { stopRinging() }
            stopRingRunnable = r
            mainHandler.postDelayed(r, durationSec.coerceIn(3, 30) * 1000L)
        } catch (_: Exception) {
            stopRinging()
        }
    }

    private fun stopRinging() {
        stopRingRunnable?.let { mainHandler.removeCallbacks(it) }
        stopRingRunnable = null
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
        } catch (_: Exception) {}
        mediaPlayer = null
    }

    @Suppress("DEPRECATION")
    private fun discoverMdnsBridges(onComplete: (List<Map<String, Any>>) -> Unit) {
        val nsd = getSystemService(Context.NSD_SERVICE) as? NsdManager
        if (nsd == null) {
            onComplete(emptyList())
            return
        }
        val discovered = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                nsd.resolveService(
                    service,
                    object : NsdManager.ResolveListener {
                        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                            val hostAddr = serviceInfo.host?.hostAddress ?: return
                            val port = serviceInfo.port
                            val key = "$hostAddr:$port"
                            synchronized(discovered) {
                                if (seen.add(key)) {
                                    val attrs = serviceInfo.attributes
                                    val tls = attrs["tls"]?.let { String(it) } == "1"
                                    val fp = attrs["fp"]?.let { String(it) } ?: ""
                                    val ts = attrs["ts"]?.let { String(it) } ?: ""
                                    discovered.add(
                                        mapOf(
                                            "name" to serviceInfo.serviceName,
                                            "host" to hostAddr,
                                            "port" to port,
                                            "tls" to tls,
                                            "fp" to fp,
                                            "ts" to ts,
                                        ),
                                    )
                                }
                            }
                        }
                    },
                )
            }
            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }

        try {
            nsd.discoverServices("_omarchy-wizard._tcp.", NsdManager.PROTOCOL_DNS_SD, listener)
            mainHandler.postDelayed({
                try {
                    nsd.stopServiceDiscovery(listener)
                } catch (_: Exception) {}
                val snapshot = synchronized(discovered) { discovered.toList() }
                onComplete(snapshot)
            }, 2200L)
        } catch (_: Exception) {
            onComplete(emptyList())
        }
    }

    private fun saveBytesToDownloads(filename: String, bytes: ByteArray): String? {
        return try {
            val safeName = filename.replace(Regex("[^A-Za-z0-9._ -]"), "_").ifBlank { "omarchy_file" }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, safeName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: return null
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                "Downloads/$safeName"
            } else {
                @Suppress("DEPRECATION")
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                dir.mkdirs()
                val file = File(dir, safeName)
                FileOutputStream(file).use { it.write(bytes) }
                file.absolutePath
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        val name = c.getString(idx)
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
        } catch (_: Exception) {}
        return uri.lastPathSegment?.substringAfterLast('/') ?: "shared_file"
    }

    private fun handleIncomingIntent(intent: Intent?, emitLive: Boolean) {
        if (intent == null) return

        // 1. Pairing QR Deep Link: omarchy-wizard://pair?host=...&port=...&token=...
        if (intent.action == Intent.ACTION_VIEW) {
            val data = intent.data
            if (data != null && data.scheme == "omarchy-wizard") {
                val uriStr = data.toString()
                if (emitLive && eventSink != null) {
                    mainHandler.post {
                        eventSink?.success(mapOf("event" to "pair_uri", "uri" to uriStr))
                    }
                } else {
                    pendingPairUri = uriStr
                }
                return
            }
        }

        if (intent.action != Intent.ACTION_SEND) return
        val mime = intent.type ?: ""
        val callerPkg = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            referrer?.host ?: ""
        } else {
            ""
        }

        // 2. Shared File / Photo (ACTION_SEND with EXTRA_STREAM)
        @Suppress("DEPRECATION")
        val streamUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (streamUri != null) {
            ioExecutor.execute {
                try {
                    val fname = queryDisplayName(streamUri)
                    val baos = ByteArrayOutputStream()
                    contentResolver.openInputStream(streamUri)?.use { input ->
                        val buf = ByteArray(16384)
                        var total = 0
                        while (true) {
                            val read = input.read(buf)
                            if (read <= 0) break
                            total += read
                            if (total > MAX_SHARE_BYTES) return@execute
                            baos.write(buf, 0, read)
                        }
                    }
                    val b64 = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
                    val payload = mapOf(
                        "event" to "share_file",
                        "filename" to fname,
                        "dataBase64" to b64,
                        "mimeType" to mime,
                        "packageName" to callerPkg,
                    )
                    if (emitLive && eventSink != null) {
                        mainHandler.post { eventSink?.success(payload) }
                    } else {
                        pendingShare = payload
                    }
                } catch (_: Exception) {}
            }
            return
        }

        // 3. Shared Text / URL (Chrome, YouTube, Spotify, etc.)
        if (!mime.startsWith("text/")) return
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim() ?: ""
        val sharedSubject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim() ?: ""
        if (sharedText.isEmpty()) return

        val payload = mapOf(
            "event" to "share",
            "text" to sharedText,
            "subject" to sharedSubject,
            "packageName" to callerPkg,
        )

        if (emitLive && eventSink != null) {
            mainHandler.post { eventSink?.success(payload) }
        } else {
            pendingShare = payload
        }
    }

    override fun onDestroy() {
        stopRinging()
        ioExecutor.shutdownNow()
        super.onDestroy()
    }
}
