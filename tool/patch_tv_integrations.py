#!/usr/bin/env python3
"""Add Cast permissions and TV discovery visibility to the generated manifest."""
from pathlib import Path
p = Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text()
perms = ['android.permission.ACCESS_NETWORK_STATE', 'android.permission.CHANGE_WIFI_MULTICAST_STATE']
for permission in perms:
    tag = f'<uses-permission android:name="{permission}" />'
    if permission not in s:
        s = s.replace('<application', '    ' + tag + '\n    <application', 1)
if '<uses-feature android:name="android.software.leanback"' not in s:
    # Do not require TV hardware: this is an optional feature for sender phones.
    s = s.replace('<application', '<uses-feature android:name="android.software.leanback" android:required="false" />\n    <application', 1)
p.write_text(s)
