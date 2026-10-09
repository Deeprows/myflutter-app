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
          "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"):
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
