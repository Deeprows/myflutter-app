# Deeprowss Windows Receiver

This Electron wrapper opens the existing hosted receiver at `https://deeprows.github.io/myflutter-app/` in a full-screen desktop window. It uses the original Deeprowss project logo.

## Build locally

```powershell
cd desktop/windows
npm install
npm run dist
```

Outputs are written to `desktop/windows/dist/`:
- `Deeprowss-Windows-Setup.exe` (NSIS installer)
- `Deeprowss-Windows-Portable.exe` (portable executable)

The GitHub Actions workflow builds both automatically. These EXE files are not Authenticode-signed by default; Windows SmartScreen may show a warning. For a public production release, sign the EXE with a trusted code-signing certificate.
