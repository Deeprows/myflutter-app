# Monitor app traffic with Cloudflare

The app downloads its lists (fixtures, highlights, movies, TV, ticker) from a
Cloudflare Worker that you own. The Worker gets the files from GitHub, keeps a
30-second copy at Cloudflare's edge and records anonymous usage. You then see:

* **Cloudflare dashboard** - Workers > your Worker > Metrics (requests, errors),
  and (if your domain is on Cloudflare) Analytics > Traffic (countries,
  status codes, bandwidth).
* **Your own page** - `https://<worker-address>/stats?token=<STATS_TOKEN>` shows
  distinct phones and requests per day, countries, app versions, files.

Streams (video) do not pass through Cloudflare; only these list downloads do.
If `deeprowss.com` is proxied (orange cloud) in Cloudflare, the match-chat
traffic to that site already shows up in that zone's Analytics.

## Setup (works from a phone browser, no computer needed)

1. dash.cloudflare.com > **Workers & Pages** > **Create** > **Hello World** >
   Deploy. Then **Edit code**, delete everything, paste `cloudflare/worker.js`,
   **Deploy**.
2. **Settings > Domains & Routes**: use the free `...workers.dev` address, or
   **Add > Custom domain** `feed.deeprowss.com` (the domain must be on
   Cloudflare).
3. **Settings > Bindings > Add > Analytics Engine**: variable name `ANALYTICS`,
   dataset `deeprowss_app`.
4. For the stats page, **Settings > Variables and Secrets > Add** (type Secret):
   * `STATS_TOKEN` - any long random text (you will use it in the stats link)
   * `CF_ACCOUNT_ID` - shown on the right of the Cloudflare dashboard home
   * `CF_API_TOKEN` - My Profile > API Tokens > Create Token > Custom token >
     permission **Account > Account Analytics > Read**
5. Open `https://<worker-address>/feed/movies.json`. You should see your movies
   JSON.
6. In the app's `lib/config.dart` set
   `static const feedBase = 'https://<worker-address>';` (no trailing slash).
   Keep the GitHub links (`fixturesUrl`, ...) set: they are the fallback if the
   Worker is ever down. Commit; the build produces the new APK.

Check: use the new APK, then open the `/stats?token=...` page (data appears
after a minute or two).

## Nothing shows up? Check in this order

1. Open `https://<worker-address>/health`. It must show
   `"analytics":true` and (for the stats page) `"stats":true`.
   * `analytics:false` -> step 3 above is missing: **Settings > Bindings >
     Add > Analytics Engine**, variable name exactly `ANALYTICS`, dataset
     `deeprowss_app`. Without it the app still works but nothing is recorded.
   * `stats:false` -> add the three secrets from step 4.
   * No `analytics` field at all -> the deployed Worker is an old copy; paste
     the current `cloudflare/worker.js` and **Deploy** again.
2. Open the app once on a phone with internet (use the APK built by GitHub
   Actions, not `flutter run` in debug, if you want the real app version).
3. Wait 1-2 minutes, then open `/stats?token=<STATS_TOKEN>`.
   "App opens" counts one launch (or a return after 30+ minutes away); a ping
   that fails is retried up to 3 times.

Data is sampled by install id, so distinct-phone counts stay accurate even at
higher traffic.

## Good to know

* **Free plan limit:** 100,000 Worker requests per day. One open app makes
  about 60 requests per hour (5 files every 5 minutes) plus pull-to-refreshes,
  so roughly 1,600 hours of app use per day fit. Beyond that the Workers Paid
  plan ($5/month) allows 10 million. If the limit is hit the app silently falls
  back to GitHub.
* **Privacy:** the app sends an anonymous random install id, the app version
  and "android". Cloudflare derives the country from the connection and also
  sees IP addresses in its own logs. Mention analytics in your privacy policy
  (and in Google Play's Data safety form if you publish there).
* **Freshness:** new items reach phones within about 10-60 seconds
  (`FEED_TTL` variable, in seconds, changes it; default 10, `0` = no edge cache). `fixtures` and `ticker` are never edge-cached, so the Live screen is always fresh.
* Tests: `node cloudflare/worker.test.mjs`.


## QR pairing for the TV receiver

The receiver page now creates a short-lived pairing room at
https://deeprowss-feed.deeprows.workers.dev/cast/create and displays its QR
code. Smart Decoder scans that QR, then exchanges WebRTC offer/answer and ICE
messages through /cast/send and /cast/poll.

Before using the QR flow:

1. Deploy the current cloudflare/worker.js to the existing
   deeprowss-feed.deeprows.workers.dev Worker.
2. Confirm that the Worker has its existing D1 binding named exactly DB.
   The QR relay creates cast_rooms and cast_signals tables automatically
   in that database; no manual SQL migration is needed.
3. Open https://deeprows.github.io/myflutter-app/receiver/. The page should
   show a QR code and a 16-character pairing code.
4. In Smart Decoder, open Send to receiver page → Scan TV QR code.

Pairing rooms expire after 15 minutes. Generate a fresh QR if one expires.
Only signalling messages pass through the Worker; the media stream itself is
peer-to-peer WebRTC. The existing local-IP/PIN method remains as a fallback.


## Premium subscriptions and receiver access

The same Worker also handles Deeprowss Premium. Keep the existing D1 binding
named `DB`, and deploy the current `cloudflare/worker.js` after changes to
subscription logic. The Worker creates `decoder_codes` and `movie_trials`
automatically.

The receiver Subscription button uses these routes:

- `POST /receiver/sub/start` and `GET /receiver/sub/verify` for Paystack checkout
- `GET /receiver/sub/status?device=<receiver-id>` to restore receiver access
- `POST /receiver/decoder/issue` and `POST /receiver/decoder/validate`
- `POST /receiver/movie-access` for the three-distinct-title trial

The Deeprowss App uses `/sub/movie-access` for signed-in accounts,
`/sub/movie-access-guest` for guest install IDs, and `/sub/decoder/issue`
for Premium Decoder numbers. Decoder numbers are linked to the Premium expiry and
stop working after it expires. A new number is issued after resubscribing
following expiry. The receiver-only subscription flow is tied to that
receiver's stored device ID; include this ID in manual WhatsApp payment
messages so the admin can activate the correct EXE / Android TV.
