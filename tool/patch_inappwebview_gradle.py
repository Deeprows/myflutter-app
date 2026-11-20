#!/usr/bin/env python3
"""Lets flutter_inappwebview build with the newest Android Gradle plugin.

The plugin's android/build.gradle asks for getDefaultProguardFile(
'proguard-android.txt'), which the newest Android build tools reject:

    `getDefaultProguardFile('proguard-android.txt')` is no longer supported
    since it includes `-dontoptimize` ...

This switches it to the optimised file the error message asks for. Run after
`flutter pub get` (the GitHub workflow does it). Safe to run more than once.
"""
import glob
import os
import sys

cache = os.environ.get("PUB_CACHE") or os.path.join(os.path.expanduser("~"), ".pub-cache")
files = []
for pattern in (
    "hosted/pub.dev/flutter_inappwebview_android-*/android/build.gradle",
    "hosted/pub.dev/flutter_inappwebview_android-*/android/build.gradle.kts",
):
    files += glob.glob(os.path.join(cache, pattern))

if not files:
    print("patch_inappwebview_gradle: plugin not found in", cache, "- nothing to do")
    sys.exit(0)

OLD = ("proguard-android.txt", "proguard-android-optimize.txt")
for path in files:
    text = open(path, encoding="utf8").read()
    if OLD[0] not in text:
        print("already fine:", path)
        continue
    open(path, "w", encoding="utf8").write(text.replace(OLD[0], OLD[1]))
    print("patched:", path)
