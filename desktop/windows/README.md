# Deeprowss Cinema for Windows

The Windows desktop app now opens the same Deeprowss receiver URL experience used by the hosted receiver page. It includes movie discovery, live TV browsing and phone-to-PC casting.

## Movies & Series

- Trending Now (TMDB weekly trending movies and series).
- Top 10 (TMDB top-rated movies).
- Trending Movies.
- Latest official YouTube trailers.
- Search across the local Deeprowss catalogue and TMDB.
- Movie / series and genre filters.
- Full movie details: overview, poster/backdrop, rating, release year, runtime, genres, director/creator, cast, trailer and similar titles.
- Play, alternate player, download link, Watch Later and Watch History.

The receiver reads the live movies.json, tv.json and app_config.json files from the repository. TMDB recommendations and details are refreshed from TMDB; receiver settings are reloaded from app_config.json every five minutes. Set tmdb.enabled, tmdb.apiKey and tmdb.language there without rebuilding the EXE. Leave apiKey empty to use the receiver's built-in TMDB key.

## Live TV and casting

- Lists all channels from the Deeprowss tv.json catalogue, grouped by category.
- Merges the IPTV Nexus online-channel feed and refreshes it periodically.
- Plays supported HLS, DASH, direct video and embed channel links where the provider/browser allows it.
- Retains phone-to-PC pairing: open Cast from Phone, scan the QR code or enter the phone address and six-digit PIN, then choose a channel in Smart Decoder on your phone to cast it here.

## Build locally

```powershell
cd desktop/windows
npm install
npm run start
npm run dist
```

Outputs are written to desktop/windows/dist/:
- Deeprowss-Cinema-Installer-1.2.0.exe
- Deeprowss-Cinema-Portable-1.2.0.exe

Playback depends on third-party providers, their embed policies, stream availability, codecs, autoplay rules and network access. Phone-to-PC casting requires both devices on the same Wi-Fi/LAN and may require allowing Deeprowss through Windows Firewall.

The GitHub Actions workflow builds both Windows packages. EXE files are not Authenticode-signed by default; Windows SmartScreen may show a warning.
