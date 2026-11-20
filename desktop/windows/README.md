# Deeprowss Cinema for Windows

The Windows desktop app focuses on two Deeprowss features only:

- **Movies & Series:** loads the current catalogue from `assets/data/movies.json` on the Deeprowss GitHub repository, with search, movie/series filters, posters and provider iframe playback.
- **Cast Live Channels:** embeds the existing Deeprowss TV receiver. Start the receiver in Smart Decoder on the mobile app, pair using the displayed address and six-digit PIN, then select a live channel on the phone to play it on the PC.

The desktop shell is Kodi-inspired, with a dark media-centre layout. It does not port unrelated football, predictions, social, betting or account screens.

## Build locally

```powershell
cd desktop/windows
npm install
npm run start
npm run dist
```

Outputs are written to `desktop/windows/dist/`:
- `Deeprowss-Cinema-Installer-1.1.0.exe`
- `Deeprowss-Cinema-Portable-1.1.0.exe`

Movies use their configured embed URLs (including Vsembed). Playback depends on the provider allowing iframe embedding and on its own availability, codecs and autoplay policy. The live-channel receiver uses the existing phone-to-PC WebSocket/WebRTC pairing flow; both devices should be on the same Wi-Fi/LAN. Some network/firewall configurations may require allowing Deeprowss through Windows Firewall.

The GitHub Actions workflow builds both Windows packages. EXE files are not Authenticode-signed by default; Windows SmartScreen may show a warning.
