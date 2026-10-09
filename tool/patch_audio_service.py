#!/usr/bin/env python3
"""Android setup for audio_service (background music + lock-screen controls).

Run after `flutter create . --platforms=android` and after
tool/patch_main_activity.py / tool/patch_background_playback.py:

    python3 tool/patch_audio_service.py

  * MainActivity.kt  - extends AudioServiceActivity (shares the Flutter engine
    with the media service)
  * AndroidManifest  - AudioService + MediaButtonReceiver, WAKE_LOCK and
    FOREGROUND_SERVICE(_MEDIA_PLAYBACK) permissions
Safe to run more than once.
"""
import glob
import sys

matches = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not matches:
    sys.exit("MainActivity.kt not found - run `flutter create . --platforms=android` first")
path = matches[0]
src = open(path, encoding="utf8").read()
if "AudioServiceActivity" not in src:
    src = src.replace(
        "import io.flutter.embedding.android.FlutterActivity",
        "import com.ryanheise.audioservice.AudioServiceActivity", 1)
    src = src.replace(": FlutterActivity()", ": AudioServiceActivity()", 1)
    open(path, "w", encoding="utf8").write(src)
    print("patched", path)

mpath = "android/app/src/main/AndroidManifest.xml"
m = open(mpath, encoding="utf8").read()
if "xmlns:tools" not in m:
    m = m.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
add = ""
for p in ("android.permission.WAKE_LOCK",
          "android.permission.FOREGROUND_SERVICE",
          "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
          "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"):
    if f'android:name="{p}"' not in m:
        add += f'    <uses-permission android:name="{p}"/>\n'
if add:
    m = m.replace("<application", add + "    <application", 1)
if "com.ryanheise.audioservice.AudioService" not in m:
    block = '''        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
    '''
    m = m.replace("</application>", block + "</application>", 1)
open(mpath, "w", encoding="utf8").write(m)
print("patched", mpath)

# ---- notification small icon -------------------------------------------
# AudioServiceConfig references drawable/ic_stat_notify. Flutter's launcher
# icon generator does not create this Android status-bar resource, so add a
# simple white vector icon explicitly; otherwise the media notification may
# fail to render on Android devices.
import os
icon_dir = "android/app/src/main/res/drawable"
os.makedirs(icon_dir, exist_ok=True)
icon_path = os.path.join(icon_dir, "ic_stat_notify.xml")
if not os.path.exists(icon_path):
    with open(icon_path, "w", encoding="utf8") as f:
        f.write("""<vector xmlns:android=\"http://schemas.android.com/apk/res/android\"
    android:width=\"24dp\" android:height=\"24dp\"
    android:viewportWidth=\"24\" android:viewportHeight=\"24\">
    <path android:fillColor=\"#FFFFFFFF\" android:pathData=\"M12,3 L12,5 C8.13,5 5,8.13 5,12 C5,15.87 8.13,19 12,19 C15.87,19 19,15.87 19,12 L21,12 C21,16.97 16.97,21 12,21 C7.03,21 3,16.97 3,12 C3,7.03 7.03,3 12,3 Z M10,8 L16,12 L10,16 Z\"/>
</vector>
""")
print("ensured", icon_path)

# ---- keep the icon in release builds -----------------------------------
# audio_service finds the notification icon by NAME at runtime
# (getIdentifier("ic_stat_notify")). Nothing references it from code, so the
# release build's resource shrinker deletes it, the media notification then
# has no valid small icon, and Android silently refuses to show it (no card
# in the notification bar or on the lock screen). This file tells the shrinker
# to keep it.
raw_dir = "android/app/src/main/res/raw"
os.makedirs(raw_dir, exist_ok=True)
keep_path = os.path.join(raw_dir, "keep.xml")
with open(keep_path, "w", encoding="utf8") as f:
    f.write("""<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_stat_notify,@mipmap/ic_launcher*,@drawable/ic_launcher*"
    tools:shrinkMode="lenient" />
""")
print("ensured", keep_path)

# ---- make sure the service is declared with the media type ---------------
m = open(mpath, encoding="utf8").read()
if "android.permission.POST_NOTIFICATIONS" not in m:
    m = m.replace("<application",
        '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application', 1)
    open(mpath, "w", encoding="utf8").write(m)
    print("added POST_NOTIFICATIONS")
