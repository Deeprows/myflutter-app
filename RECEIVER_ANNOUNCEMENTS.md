# Receiver ticker and notices

These settings are for the **receiver products only**. They do not change the
original Deeprowss mobile app ticker or its mobile notice.

- `assets/data/receiver_ticker.json` controls the receiver ticker.
- `assets/data/receiver_notice.json` controls receiver pop-up notices.
- `assets/receiver/remote-announcements.js` loads both files from the live
  GitHub raw URLs and refreshes them every 60 seconds.

The same receiver page is used by:
- the hosted URL receiver at
  `https://deeprows.github.io/myflutter-app/receiver/`
- Deeprowss Windows EXE (the build bundles the receiver files)
- Deeprowss Android TV Receiver (the app opens the hosted receiver URL)

Therefore, changing either JSON updates the hosted receiver and both native
wrappers without rebuilding them, provided the device is online. The Windows
build also bundles the JSON files for offline fallback, but the announcement
script deliberately fetches the current live JSON when online.

## Ticker example

```json
{
  "enabled": true,
  "speed": 36,
  "items": ["Thank you for choosing Deeprowss."]
}
```

## Notice example

```json
{
  "enabled": true,
  "id": "receiver-notice-001",
  "title": "Deeprowss Notice",
  "message": "Thank you for choosing Deeprowss.",
  "popup": true,
  "beep": true,
  "button_text": "",
  "button_url": "",
  "ok_text": "Close",
  "expires": "",
  "updated_at": ""
}
```

Change `id` whenever you publish a new notice. A notice is shown once per ID
on each receiver installation/browser profile. The optional beep requires a
user interaction first because browsers and embedded WebViews restrict
automatic audio.

## Closed-app notifications

The ticker and pop-up are in-page features. They refresh while the receiver is
running. They do **not** wake a closed Windows EXE, a closed Android TV app,
or a closed browser tab. That requires a separate push-delivery setup:
Firebase Cloud Messaging for Android TV and a Windows notification/push
provider (or Web Push with VAPID for supported browser installs). Publishing
a new JSON file alone cannot deliver a notification to a process that is not
running. Keep all service-account credentials and VAPID private keys in
provider secrets, never in these public JSON files.
