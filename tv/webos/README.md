# LG webOS TV package

This project opens the existing hosted Deeprowss receiver. It uses the official webOS TV CLI to produce an `.ipk` package.

Local build (Node.js installed):

```bash
npm install -g @webosose/ares-cli
ares-package ./tv/webos -o ./dist
```

GitHub Actions performs this packaging automatically and attaches the resulting `Deeprowss-LG-webOS.ipk` to versioned releases. Install/testing on a TV requires Developer Mode and device registration with the webOS CLI. Public LG Content Store distribution requires LG's developer and review process.
