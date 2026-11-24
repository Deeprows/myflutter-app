# Private repository migration (Deeprowss)

This migration is deliberately staged. **Do not change the repository visibility until every activation check below passes.** Existing app URLs are not changed by the Worker proxy code alone.

## What the Worker now supports

The Worker source adds two public proxy route families:

- `/public/data/<filename>` — allowlisted public JSON configuration and feed files from `assets/data/`.
- `/public/releases/<tag>/<filename>` — allowlisted Deeprowss release binaries.

Both routes work while the repository is public without a GitHub secret. When the repository becomes private, they use the Worker's `GITHUB_TOKEN` secret to read the private repository and its release assets. The regular `/feed/*.json` routes also use that token when configured.

The proxy only exposes an explicit allowlist. It does not provide arbitrary repository-file access.

## Required activation steps

1. In Cloudflare, open Workers & Pages and select `deeprowss-feed`.
2. Replace its deployed code with the current `cloudflare/worker.js` from this repository and deploy it.
3. In Worker Settings → Variables and Secrets, add a **Secret** named `GITHUB_TOKEN`.
   - Use a fine-grained GitHub personal access token.
   - Repository access: only `Deeprows/myflutter-app`.
   - Permissions: **Contents: Read-only** and **Metadata: Read-only**. Release metadata/assets are read through the repository API.
   - Never put this token in app code, JSON files, or GitHub commits.
4. Test these public URLs while the repository is still public:
   - `https://deeprowss-feed.deeprows.workers.dev/health`
   - `https://deeprowss-feed.deeprows.workers.dev/public/data/app_config.json`
   - `https://deeprowss-feed.deeprows.workers.dev/public/data/download_links.json`
   - `https://deeprowss-feed.deeprows.workers.dev/public/releases/v1.3.7/Deeprowss-v1.3.7.apk`
5. Confirm the JSON endpoints return JSON and the APK endpoint downloads an APK (not a JSON error page).
6. Only after that, update app/receiver config URLs and release download URLs to the Worker endpoints, publish and test the updated app/receiver.
7. Confirm Cloudflare Pages is connected and can deploy the private repository. Also decide what to do with the GitHub Pages deployment job in `.github/workflows/build.yml`: GitHub Pages on GitHub Free requires a public repository, so a private repo may stop that secondary Pages site. The Cloudflare Pages site is a separate deployment and must be checked in its own dashboard.
8. Only after all app, receiver, update, download and hosting tests pass should repository visibility be changed to private.

## Current status

- [x] Worker proxy implementation committed.
- [x] Unit tests added for public fallback and authenticated private-repository proxy paths.
- [ ] Deploy the updated Worker in Cloudflare.
- [ ] Add the Cloudflare Worker secret `GITHUB_TOKEN`.
- [ ] Switch app and receiver public URLs to the Worker.
- [ ] Verify APK updater and all release downloads through the Worker.
- [ ] Verify Cloudflare Pages and resolve the GitHub Pages deployment dependency.
- [ ] Change repository visibility (manual final step only).

**Safety rule:** keep the repository public until every unchecked activation item is complete. No visibility change is performed by this migration.
