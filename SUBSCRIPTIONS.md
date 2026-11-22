# Free & Premium (manual payment; Paystack coming soon)

On start the app shows a plans page.

* **Free** - browse the movie catalogue and watch up to **3 distinct movie or
  series titles**. After the third title, Play, Alternate player and Download
  actions open the Premium upgrade gate. Smart Decoder is Premium-only.
* **Premium** - ₦2,000 / month or ₦20,000 / year (or the current prices from
  Worker configuration). People outside Nigeria see an estimate in their own
  currency; the actual OPay transfer remains in naira, while USDT payers send
  the equivalent amount on TRC20.
* **Manual payment** - users choose OPay or USDT TRC20, send the amount, then
  attach their receipt in WhatsApp. The message includes their account/device
  ID and selected plan. After confirming the receipt, the admin grants the exact number of days selected in the plan dropdown from
  /sub/admin. The grant now issues
  the Premium Decoder number in the admin confirmation, which users can enter
  on the EXE / Android TV. The helpline is **+234 704 162 9630**.
* **Paystack** is shown as **Coming Soon** and no checkout or payment
  verification action is exposed until its setup is ready.

Premium people skip the plans page and go straight into the app.

## How it works

```
App -> WhatsApp receipt + account ID -> admin /sub/admin grant -> D1 Premium
EXE / Android TV -> WhatsApp receipt + device ID -> admin /sub/admin grant
Admin grant -> server-issued Decoder number -> /receiver/decoder/validate
Movie actions -> /sub/movie-access or /receiver/movie-access -> D1 trial usage
Paystack /sub/start and /sub/verify remain dormant until checkout is configured.
```

The Paystack secret key lives only in the Worker. A payment is counted once
per Paystack reference, and only when it is a successful NGN payment of at
least the selected price. One paid month = 31 days, one paid year = 366 days;
paying again stacks on the time that is left. The app and receiver show the same duration-based prices and local-currency
estimate from /sub/config. Both show the same OPay and USDT TRC20 payment
accounts from assets/data/payment_accounts.json, with receipt confirmation
through WhatsApp. Paystack is labelled Coming Soon in both interfaces.

## One-time setup (phone browser is enough)

1. **Paystack** > Settings > API Keys & Webhooks
   * copy the **Secret key** (start with `sk_test_...` to try it, then switch
     to `sk_live_...`)
   * set **Webhook URL** to `https://deeprowss-feed.deeprows.workers.dev/sub/webhook`
2. *(optional, for monthly auto-renew)* Paystack > Products > **Plans** >
   Create plan: ₦2,000, monthly. Copy its plan code (`PLN_...`).
3. **Cloudflare** > Storage & databases > **D1** > Create database
   `deeprowss_subs`. Then your Worker > Settings > Bindings > Add > **D1
   database**, variable name exactly `DB`. (The tables create themselves.)
4. Worker > Settings > Variables and Secrets:
   * `PAYSTACK_SECRET_KEY` (secret) - from step 1
   * `PAYSTACK_PLAN_CODE` (optional) - from step 2; without it the auto-renew
     switch is hidden and each month is paid by hand
   * `ADMIN_TOKEN` (secret) - any long random text, for the admin page
   * `PRICE_NGN` (optional) - default 2000; change it here, no new APK needed
   * `PRICE_NGN_YEAR` (optional) - yearly price, default 20000 (two months free)
   * `PAYSTACK_PLAN_CODE_YEAR` (optional) - a yearly Paystack plan for card auto-renew
5. Paste the new `cloudflare/worker.js` into the Worker and **Deploy**.
6. Open `https://deeprowss-feed.deeprows.workers.dev/health`. It must show
   `"subscriptions":true`.
7. Pay once yourself with the test key (Paystack gives test cards), then
   switch to the live key.

## Manual (WhatsApp) payers

1. Put your link in `lib/config.dart`: `whatsappUrl = 'https://wa.me/<number>'`
   (country code, no `+`).
2. When someone pays you, their WhatsApp message contains "My ID: ...",
   the plan duration and payment method. Confirm the receipt before granting.
3. Open https://deeprowss-feed.deeprows.workers.dev/sub/admin?token=<ADMIN_TOKEN>,
   paste the ID, enter the exact plan duration in days shown in the WhatsApp
   receipt (e.g. 30 or 365), and press **Grant**. The confirmation includes
   the issued 10-digit Decoder
   number. Enter **0** to switch someone off; this also expires their Decoder
   number. The page also lists who is premium.
4. The phone picks it up the next time the app opens or when the person
   reopens the plans page.

## Settings in the app (`lib/config.dart`)

| Setting                 | Meaning                                                    |
|-------------------------|------------------------------------------------------------|
| `plansEnabled`          | false = no plans page and no ads for anyone                |
| `showPlansEveryStart`   | true: plans page on every launch for non-premium people    |
| `adIntervalMinutes`     | minutes of use between support pages (15)                  |
| `adRetryMinutes`        | if the support page can't load, ask again after this many  |
| `supportUrl`            | the ad / smart link (empty = no ads)                       |
| `whatsappUrl`           | manual-payment chat (empty = "coming soon" message)        |
| `supportOnCardTap`      | the old tap-a-card trigger; **off**                        |

## Good to know

* App Premium is tied to the signed-in Gmail account. Receiver-only checkout
  is tied to that EXE / Android TV receiver's device ID. Keep the device ID
  when contacting the WhatsApp helpline or requesting manual activation.
* A Premium Decoder number is generated by the Worker and tied to the
  subscription owner. It stops validating when that subscription expires.
  Resubscribing after expiry issues a fresh number; a renewal before expiry
  extends the current number's expiry.
* The ad clock counts only time the app is open on screen, and keeps counting
  across launches. It pauses on the plans / payment pages.
* Auto-renew works for cards only (Paystack limitation). Bank-transfer and
  USSD payers pay again each month. To stop an auto-renewing customer, use
  Paystack > Customers > Subscriptions.
* Exchange rates come from a free public API and are cached for 6 hours. If
  it is down, the naira price is shown alone.
* Tests: `node --no-warnings cloudflare/subscription.test.mjs` (Node 22+).
* If you ever publish on Google Play: Play requires Google Play Billing for
  digital subscriptions, so Paystack is fine for your own APK / GitHub
  downloads but not for a Play Store release.


## Receiver / EXE / Android TV Premium gate

The hosted receiver page (used by the website, Windows EXE and Android TV app)
allows three distinct movie/series titles per visitor. The Play, Alternate
player and Download buttons all check the same server-side allowance. The
count is stored in D1, not only in browser storage.

Visitors without the Deeprowss App can open **Subscription** on the receiver
home screen, pay by Paystack using their e-mail, and receive a Decoder number
for that receiver. App subscribers get their Decoder number from Smart
Decoder in the app and enter it on the receiver home screen. The number is
checked against the subscription expiry every time access is validated.

The Worker creates these tables automatically in the existing `DB` D1
binding: `decoder_codes` and `movie_trials`. New Worker routes:

- `POST /receiver/sub/start`, `GET /receiver/sub/verify`, `GET /receiver/sub/status`
- `POST /receiver/decoder/issue`, `POST /receiver/decoder/validate`
- `POST /receiver/movie-access`
- `POST /sub/decoder/issue`, `POST /sub/movie-access` (signed-in app account),
  and `POST /sub/movie-access-guest` (app guest install ID)

**Deploy the updated `cloudflare/worker.js` to the existing Worker** before
expecting the new gate or Decoder numbers to work. The receiver page and app
source are separate deployments; GitHub Actions builds the app/EXE and
publishes the receiver files, but it does not deploy the Cloudflare Worker.
