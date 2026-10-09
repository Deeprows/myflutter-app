#!/usr/bin/env python3
"""Adds background playback (foreground media service) to the Android project.

Run after `flutter create . --platforms=android` AND after
tool/patch_main_activity.py (the GitHub workflow does it):

    python3 tool/patch_background_playback.py

  * android/.../PlaybackService.kt  - foreground service with a "Playing in
    background" notification (Stop button) so playback survives minimising
    the app and locking the screen
  * MainActivity.kt                 - `footbolive/playback` MethodChannel
    (start / stop) used by lib/services/background_playback.dart
  * AndroidManifest.xml             - service + FOREGROUND_SERVICE_MEDIA_PLAYBACK
    and WAKE_LOCK permissions
Safe to run more than once.
"""
import glob
import re
import sys

matches = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not matches:
    sys.exit("MainActivity.kt not found - run `flutter create . --platforms=android` first")
activity = matches[0]
src = open(activity, encoding="utf8").read()
pkg = re.search(r"^package\s+([\w.]+)", src, re.M).group(1)
folder = activity.rsplit("/", 1)[0]

service = '''package __PKG__

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.net.wifi.WifiManager
import android.os.IBinder
import android.os.PowerManager

/** Keeps the process alive (and shows a notification) while a video plays. */
class PlaybackService : Service() {
    companion object {
        const val CHANNEL = "playback"
        const val NOTIFICATION_ID = 4107
        const val ACTION_STOP = "__PKG__.STOP_PLAYBACK"

        /** Set by MainActivity: tells Flutter that Stop was tapped. */
        @Volatile
        var onStopRequested: (() -> Unit)? = null
    }

    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    /** Keeps the CPU and Wi-Fi awake while the screen is off, otherwise the stream stalls. */
    private fun lock() {
        try {
            if (wake == null) {
                wake = (getSystemService(POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "deeprowss:playback")
                    .apply { setReferenceCounted(false) }
            }
            if (wake?.isHeld != true) wake?.acquire(6 * 60 * 60 * 1000L)
            if (wifi == null) {
                wifi = (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager)
                    .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "deeprowss:playback")
                    .apply { setReferenceCounted(false) }
            }
            if (wifi?.isHeld != true) wifi?.acquire()
        } catch (e: Exception) {
        }
    }

    private fun unlock() {
        try {
            if (wake?.isHeld == true) wake?.release()
            if (wifi?.isHeld == true) wifi?.release()
        } catch (e: Exception) {
        }
    }

    override fun onDestroy() {
        unlock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            onStopRequested?.invoke()
            shutDown()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra("title") ?: "Deeprowss"
        lock()
        val notification = build(title)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun build(title: String): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm != null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Background playback", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "Shown while a video keeps playing in the background" }
            )
        }
        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val open = PendingIntent.getActivity(this, 0, launch, immutable or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, PlaybackService::class.java).setAction(ACTION_STOP),
            immutable or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val icon = resources.getIdentifier("ic_stat_notify", "drawable", packageName)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        @Suppress("DEPRECATION")
        return builder
            .setSmallIcon(if (icon != 0) icon else android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText("Playing in background")
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stop)
            .build()
    }

    private fun shutDown() {
        unlock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    /** App swiped away from recents: stop playing. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        shutDown()
        super.onTaskRemoved(rootIntent)
    }
}
'''.replace("__PKG__", pkg)
open(f"{folder}/PlaybackService.kt", "w", encoding="utf8").write(service)
print("wrote", f"{folder}/PlaybackService.kt")

# ---- MainActivity: channel ----------------------------------------------
if "setupPlayback" not in src:
    for imp in ("import android.content.Intent", "import android.os.Build"):
        if imp not in src:
            src = re.sub(r"^(package\s+[\w.]+\s*\n)", r"\1\n" + imp + "\n", src, count=1, flags=re.M)
    src = src.replace(
        "super.configureFlutterEngine(flutterEngine)",
        "super.configureFlutterEngine(flutterEngine)\n        setupPlayback(flutterEngine)", 1)
    method = '''
    private fun setupPlayback(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "footbolive/playback")
        PlaybackService.onStopRequested = {
            runOnUiThread { channel.invokeMethod("stopRequested", null) }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    var ok = true
                    try {
                        val i = Intent(this, PlaybackService::class.java)
                            .putExtra("title", call.argument<String>("title") ?: "Deeprowss")
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
                        else startService(i)
                    } catch (e: Exception) {
                        ok = false
                    }
                    result.success(ok)
                }
                "stop" -> {
                    try {
                        stopService(Intent(this, PlaybackService::class.java))
                    } catch (e: Exception) {
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
'''
    idx = src.rstrip().rfind("}")
    src = src[:idx] + method + "}\n"
    open(activity, "w", encoding="utf8").write(src)
    print("patched", activity)

# ---- manifest -----------------------------------------------------------
mpath = "android/app/src/main/AndroidManifest.xml"
m = open(mpath, encoding="utf8").read()
add = ""
for p in ("android.permission.FOREGROUND_SERVICE",
          "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
          "android.permission.WAKE_LOCK"):
    if p not in m:
        add += f'    <uses-permission android:name="{p}"/>\n'
if add:
    m = m.replace("<application", add + "    <application", 1)
if "PlaybackService" not in m:
    m = m.replace(
        "</application>",
        '    <service android:name=".PlaybackService" android:exported="false" '
        'android:foregroundServiceType="mediaPlayback"/>\n    </application>', 1)
open(mpath, "w", encoding="utf8").write(m)
print("patched", mpath)
