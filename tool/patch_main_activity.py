#!/usr/bin/env python3
"""Replaces the generated MainActivity with one that exposes picture-in-picture.

Run after `flutter create . --platforms=android` (the GitHub workflow does it):

    python3 tool/patch_main_activity.py

Provides the `footbolive/pip` MethodChannel used by lib/services/pip_service.dart
and creates the push notification channels ("kickoff" = heads-up alerts,
"content" = new highlights / movies) used by the Firebase messages.
"""
import glob
import re
import sys

matches = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not matches:
    sys.exit("MainActivity.kt not found - run `flutter create . --platforms=android` first")
path = matches[0]
pkg = re.search(r"^package\s+([\w.]+)", open(path, encoding="utf8").read(), re.M).group(1)

code = f'''package {pkg}

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {{
    override fun onCreate(savedInstanceState: Bundle?) {{
        super.onCreate(savedInstanceState)
        createPushChannels()
    }}

    private fun createPushChannels() {{
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        // Android cannot change a channel after it exists, so once per
        // install remove the old ones; they are recreated just below with
        // "show on the lock screen" turned on.
        val prefs = getSharedPreferences("push_channels", MODE_PRIVATE)
        if (!prefs.getBoolean("lockscreen_public_v1", false)) {{
            nm.deleteNotificationChannel("kickoff")
            nm.deleteNotificationChannel("content")
            nm.deleteNotificationChannel("social")
            prefs.edit().putBoolean("lockscreen_public_v1", true).apply()
        }}
        val kickoff = NotificationChannel(
            "kickoff", "Live match alerts", NotificationManager.IMPORTANCE_HIGH
        ).apply {{
            description = "Kick-off reminders and match start alerts"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
        }}
        val content = NotificationChannel(
            "content", "New highlights and movies", NotificationManager.IMPORTANCE_DEFAULT
        ).apply {{
            description = "New highlights and movies added to Deeprowss"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }}
        val social = NotificationChannel(
            "social", "Follows, likes and comments", NotificationManager.IMPORTANCE_HIGH
        ).apply {{
            description = "When someone follows you, likes your post or comments on it"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
        }}
        nm.createNotificationChannel(kickoff)
        nm.createNotificationChannel(content)
        nm.createNotificationChannel(social)
    }}

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "footbolive/pip")
            .setMethodCallHandler {{ call, result ->
                when (call.method) {{
                    "isAvailable" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    )
                    "enter" -> {{
                        var ok = false
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {{
                            try {{
                                val params = PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(16, 9))
                                    .build()
                                ok = enterPictureInPictureMode(params)
                            }} catch (e: Exception) {{
                                ok = false
                            }}
                        }}
                        result.success(ok)
                    }}
                    else -> result.notImplemented()
                }}
            }}
    }}
}}
'''
open(path, "w", encoding="utf8").write(code)
print("patched", path)
