#!/usr/bin/env python3
"""Add Google's Android Cast Sender SDK configuration after flutter create."""
from pathlib import Path
import os, re, sys

app = Path('android/app/build.gradle.kts')
if not app.exists():
    app = Path('android/app/build.gradle')
if not app.exists():
    sys.exit('Android Gradle file not found; run flutter create . --platforms=android first')
s = app.read_text()
# The current Cast Sender SDK requires Android API 24 or later.
if app.name.endswith('.kts'):
    s = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', s)
else:
    s = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24', s)
if 'play-services-cast-framework' not in s:
    dep = 'implementation("com.google.android.gms:play-services-cast-framework:23.0.0")'
    if app.name.endswith('.kts'):
        s = re.sub(r'dependencies\s*\{', lambda m: m.group(0) + '\n    ' + dep, s, count=1)
    else:
        s = re.sub(r'dependencies\s*\{', lambda m: m.group(0) + '\n    ' + dep.replace('implementation("','implementation \'').replace('")',"'"), s, count=1)
    app.write_text(s)
else:
    app.write_text(s)

# Configure the registered Web Receiver application ID; the default receiver
# remains functional without a custom ID.
receiver_id = os.environ.get('DEEPROWSS_CAST_RECEIVER_APP_ID', 'CC1AD845').strip() or 'CC1AD845'
values = Path('android/app/src/main/res/values')
values.mkdir(parents=True, exist_ok=True)
strings = values / 'strings.xml'
xml = strings.read_text() if strings.exists() else '<resources>\n</resources>\n'
if 'deeprowss_cast_receiver_app_id' in xml:
    xml = re.sub(r'<string name="deeprowss_cast_receiver_app_id">.*?</string>',
                 f'<string name="deeprowss_cast_receiver_app_id">{receiver_id}</string>', xml)
else:
    xml = xml.replace('</resources>', f'    <string name="deeprowss_cast_receiver_app_id">{receiver_id}</string>\n</resources>')
strings.write_text(xml)

manifest = Path('android/app/src/main/AndroidManifest.xml')
m = manifest.read_text()
meta = '<meta-data android:name="com.google.android.gms.cast.framework.OPTIONS_PROVIDER_CLASS_NAME" android:value="com.deeprows.footbolive.CastOptionsProvider" />'
if 'OPTIONS_PROVIDER_CLASS_NAME' not in m:
    m = re.sub(r'(<application\b[^>]*>)', r'\1\n        ' + meta, m, count=1)
manifest.write_text(m)
print('Google Cast SDK configured; receiver ID:', receiver_id)
