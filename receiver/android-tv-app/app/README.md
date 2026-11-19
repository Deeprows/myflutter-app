# Deeprowss TV Receiver (Android TV)

This is the dedicated Android TV / Google TV receiver app for Deeprowss's local WebRTC screen-mirroring mode.

## Build and install

1. Open this `android-tv-app` folder in Android Studio (Giraffe or newer).
2. Let Gradle sync and build the `app` debug or release variant.
3. Install the APK on an Android TV / Google TV device.
4. Open **Deeprowss TV Receiver**. Enter the phone address (for example `192.168.1.20:12345`) and six-digit pairing code shown in Deeprowss on the phone.
5. The app opens the secure hosted receiver page and connects to the phone.

The phone and TV must be on the same Wi-Fi/LAN. The TV app loads the HTTPS-hosted receiver page and connects to the phone over the local network; it receives the WebRTC video stream directly. No permanent cloud relay is used. Android TV's WebView must include WebRTC support; if a manufacturer's WebView is too old, use a current TV browser or update Android System WebView.

## Security and limitations

- The phone hosts a temporary LAN-only HTTP/WebSocket signalling endpoint with a random six-digit pairing code. Stop mirroring to close it.
- WebRTC video is peer-to-peer. STUN is used for ICE discovery; on a typical home LAN the video path remains local.
- This receiver is for Deeprowss screen mirroring. Google Cast media playback continues to use the separate Cast Web Receiver in `../deeprowss-cast-receiver/`.
- DRM-protected app surfaces may appear black. Screen capture requires Android's explicit user consent.
