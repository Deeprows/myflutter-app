#!/usr/bin/env python3
"""Patches the generated android/app/src/main/AndroidManifest.xml.

Run after `flutter create . --platforms=android` (the GitHub workflow does it):

    python3 tool/patch_android_manifest.py

Adds what release builds and background downloads need:
  * INTERNET (flutter create only adds it for debug builds)
  * POST_NOTIFICATIONS (Android 13+ download notifications)
  * FOREGROUND_SERVICE / FOREGROUND_SERVICE_DATA_SYNC (background downloads)
  * WRITE_EXTERNAL_STORAGE up to Android 9 (saving to the Downloads folder)
  * cleartext traffic (plain http:// streams)
  * removes WorkManager's default initializer so flutter_downloader can start
    its own, and sets the app label.
"""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "android/app/src/main/AndroidManifest.xml"
s = open(path, encoding="utf8").read()

if "xmlns:tools" not in s:
    s = s.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)

perms = [
    "android.permission.INTERNET",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.REQUEST_INSTALL_PACKAGES",  # install Deeprows Browser
    "android.permission.READ_MEDIA_VIDEO",  # Player tab: phone videos (Android 13+)
    "android.permission.READ_MEDIA_AUDIO",  # Player tab: phone music (Android 13+)
]
add = ""
for p in perms:
    if p not in s:
        add += f'    <uses-permission android:name="{p}"/>\n'
if "READ_EXTERNAL_STORAGE" not in s:
    add += ('    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" '
            'android:maxSdkVersion="32"/>\n')
if "WRITE_EXTERNAL_STORAGE" not in s:
    add += ('    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" '
            'android:maxSdkVersion="28"/>\n')
if add:
    s = s.replace("<application", add + "    <application", 1)

if "usesCleartextTraffic" not in s:
    s = s.replace("<application", '<application android:usesCleartextTraffic="true"', 1)

# Android 11+ only lets an app see another app that is listed in <queries>.
# The package name comes from lib/config.dart (partnerBrowserPackage).
try:
    cfg = open("lib/config.dart", encoding="utf8").read()
    m = re.search(r"partnerBrowserPackage\s*=\s*'([^']+)'", cfg)
    partner = m.group(1).strip() if m else ""
except OSError:
    partner = ""
if partner and f'android:name="{partner}"' not in s:
    tag = f'<package android:name="{partner}"/>'
    if "<queries>" in s:
        s = s.replace("<queries>", "<queries>\n        " + tag, 1)
    else:
        s = s.replace("<application", f"<queries>\n        {tag}\n    </queries>\n    <application", 1)

s = re.sub(r'android:label="[^"]*"', 'android:label="Deeprowss"', s, count=1)

if "WorkManagerInitializer" not in s:
    block = (
        '<provider android:name="androidx.startup.InitializationProvider" '
        'android:authorities="${applicationId}.androidx-startup" '
        'android:exported="false" tools:node="merge">\n'
        '            <meta-data android:name="androidx.work.WorkManagerInitializer" '
        'android:value="androidx.startup" tools:node="remove"/>\n'
        '        </provider>\n        '
    )
    s = s.replace("<activity", block + "<activity", 1)

if "supportsPictureInPicture" not in s:
    s = s.replace("<activity", '<activity android:supportsPictureInPicture="true"', 1)

open(path, "w", encoding="utf8").write(s)
print("patched", path)
