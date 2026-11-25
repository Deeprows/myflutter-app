from pathlib import Path
import re
g=Path("android/app/build.gradle.kts")
m=Path("android/app/src/main/AndroidManifest.xml")
if not g.exists() or not m.exists(): raise SystemExit("Generate Android project first.")
s=g.read_text()
s,n=re.subn(r'applicationId\s*=\s*"[^"]+"','applicationId = "com.deeprows.decoder"',s,count=1)
if n!=1: raise SystemExit("applicationId not found")
g.write_text(s)
s=m.read_text()
s,n=re.subn(r'android:label="[^"]+"','android:label="Deeprowss Decoder"',s,count=1)
if n!=1: raise SystemExit("Android label not found")
m.write_text(s)
