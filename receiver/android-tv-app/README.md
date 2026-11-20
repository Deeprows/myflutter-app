# Deeprowss Android TV Receiver

Builds a dedicated Android TV / Google TV APK for the existing Deeprowss hosted receiver.

The app uses the existing project receiver URL and branding. It is separate from the main Flutter phone APK.

GitHub Actions builds it on every version tag (`v*`) and attaches `Deeprowss-Android-TV.apk` to the GitHub Release. The build reuses `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, and `KEY_PASSWORD` if configured in repository secrets. Configure the same permanent keystore for every release so users can update without uninstalling.

A debug-signed fallback is available for first-time testing only. Do not use that fallback for public updates.
