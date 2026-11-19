# Deeprowss Android casting integrations

## Included in this patch

The Google Cast sender SDK requires Android 7.0 (API 24) or newer; the build patch raises the app minimum SDK to API 24.

- **Google Cast sender SDK**: Android Cast Framework discovery/picker, media loading, play/pause/stop, seek and receiver-volume bridge. It uses the Default Media Receiver (`CC1AD845`) until a custom receiver ID is configured.
- **Deeprowss Cast Web Receiver**: a CAF receiver shell is in `receiver/deeprowss-cast-receiver/`. Host it over HTTPS and register it in the Google Cast SDK Developer Console. Set the resulting ID in GitHub Actions repository variable `DEEPROWSS_CAST_RECEIVER_APP_ID` to use it in release builds.
- **Existing DLNA/UPnP**: the current decoder's direct-TV stream relay, saved devices, recent sessions, playback controls and background service are retained.
- **Manufacturer remote adapters**: Roku ECP, LG webOS WebSocket registration/key events and Samsung Smart TV remote WebSocket commands are available from the Remote tab. Pairing/approval varies by TV and firmware. IP addresses must be on the same local network.
- **Native Android screen mirroring**: opens Android's Cast / Wi-Fi Display settings, allowing compatible Chromecast/Google TV/Miracast devices to receive the system projection.
- **Subscription**: no new entitlement or payment logic is introduced. The existing `SubscriptionService` and Plans screen remain in place.

## Platform limitations (important)

- **AirPlay sender is not implemented on Android**. Apple's AirPlay sender APIs are not a general Android SDK. Some TVs expose DLNA or Google Cast alongside AirPlay; Deeprowss uses those supported routes instead.
- The Deeprowss Web Receiver is a **Cast media receiver**, not a custom whole-phone mirroring endpoint. It receives media URLs sent through Google Cast. Whole-screen mirroring uses Android's native system receiver path.
- An app-controlled MediaProjection-to-Deeprowss-receiver pipeline would additionally require an Android foreground capture service, real-time video encoder, WebRTC/signalling service, receiver authentication and a deployed receiver. This patch does not claim that MediaProjection permission alone sends the screen.
- Google Cast can only play media URLs/formats accepted by the receiver. Web embeds/iframes are not converted into direct media streams; local files and streams requiring custom Referer/User-Agent headers are not loaded through the Google Cast bridge in this iteration. Existing DLNA relay remains available for supported direct streams.
- Google Cast requires Google Play services and a Cast-compatible receiver. TV remote commands depend on model, firmware, local-network permissions and pairing approval. A successful socket connection does not guarantee every key is supported.

## Build

The repository generates its Android project in CI with `flutter create . --platforms=android`. The workflow now runs `tool/patch_google_cast.py`, `tool/patch_tv_integrations.py` and `tool/patch_google_cast_native.py` after Android project generation. Local builds should run the same scripts in the same order after `flutter create` and `flutter pub get`.
