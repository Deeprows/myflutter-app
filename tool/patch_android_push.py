#!/usr/bin/env python3
"""Android setup for Firebase push notifications.

Run after `flutter create . --platforms=android` (the GitHub workflow does it):

    python3 tool/patch_android_push.py

  * AndroidManifest: default FCM notification channel / icon / colour
  * res/drawable/ic_stat_notify.xml  (small white status-bar icon)
  * res/values/push_colors.xml
  * android/app minSdk -> 24 (Firebase needs at least 23)

Firebase itself is configured in Dart (lib/services/push_service.dart), so no
google-services.json / Gradle plugin is needed.
"""
import glob
import os
import re
import sys

manifest = sys.argv[1] if len(sys.argv) > 1 else "android/app/src/main/AndroidManifest.xml"
res_dir = os.path.join(os.path.dirname(manifest), "res")

# ---- manifest meta-data -------------------------------------------------
s = open(manifest, encoding="utf8").read()
if "default_notification_channel_id" not in s:
    meta = (
        '    <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id"'
        ' android:value="content"/>\n'
        '        <meta-data android:name="com.google.firebase.messaging.default_notification_icon"'
        ' android:resource="@drawable/ic_stat_notify"/>\n'
        '        <meta-data android:name="com.google.firebase.messaging.default_notification_color"'
        ' android:resource="@color/push_accent"/>\n    '
    )
    s = s.replace("</application>", meta + "</application>", 1)
    open(manifest, "w", encoding="utf8").write(s)
    print("patched", manifest)

# ---- resources ----------------------------------------------------------
os.makedirs(os.path.join(res_dir, "drawable"), exist_ok=True)
os.makedirs(os.path.join(res_dir, "values"), exist_ok=True)

open(os.path.join(res_dir, "drawable", "ic_stat_notify.xml"), "w", encoding="utf8").write(
    '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,16v-5c0,-3.07 -1.64,-5.64 -4.5,-6.32V4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 -1.5,1.5v0.68C7.63,5.36 6,7.92 6,11v5l-2,2v1h16v-1l-2,-2z" />
</vector>
''')
open(os.path.join(res_dir, "values", "push_colors.xml"), "w", encoding="utf8").write(
    '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="push_accent">#FFFF1744</color>
</resources>
''')
print("wrote push resources in", res_dir)

# ---- minSdk -------------------------------------------------------------
gradles = glob.glob("android/app/build.gradle*")
if not gradles:
    sys.exit("android/app/build.gradle(.kts) not found")
g = gradles[0]
t = open(g, encoding="utf8").read()
t2 = re.sub(r"(minSdk(?:Version)?\s*=?\s*)flutter\.minSdkVersion", r"\g<1>24", t)
if t2 != t:
    open(g, "w", encoding="utf8").write(t2)
    print("minSdk set to 24 in", g)
else:
    print("minSdk left unchanged in", g)
