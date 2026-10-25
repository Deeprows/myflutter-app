/**
 * Deeprowss feed proxy + anonymous usage monitor (Cloudflare Worker).
 *
 *   App -> https://feed.<your-domain>/feed/movies.json -> this Worker
 *                                                               |-> GitHub raw
 *                                                               '-> Analytics Engine
 *
 * Analytics:
 *   POST /analytics
 *   Records anonymous app_open events.
 *
 * Stats:
 *   /stats?token=<STATS_TOKEN>
 *
 * Settings:
 *   GITHUB_RAW_BASE  optional
 *   FEED_TTL         optional, default 10 (seconds; 0 = no edge cache)
 *   STATS_TOKEN      secret
 *   CF_ACCOUNT_ID    secret
 *   CF_API_TOKEN     secret
 *   ANALYTICS        Analytics Engine binding
 *
 * Premium subscriptions (Paystack + D1), see SUBSCRIPTIONS.md:
 *   GET  /sub/config   price, local-currency equivalent
 *   POST /sub/start    creates a Paystack checkout
 *   GET  /sub/verify   confirms a payment after checkout
 *   GET  /sub/status   is this install premium?
 *   POST /sub/webhook  Paystack events (signature checked)
 *   POST /sub/restore  move a paid subscription to a new phone
 *   /sub/admin         grant / revoke manually (WhatsApp payers), make and
 *                      hand out ad-free tokens, see token requests
 *   POST /sub/token/request  a phone asks for an ad-free token
 *   GET  /sub/token/mine     has my request been answered? (token ready?)
 *   POST /sub/token/redeem   a phone turns a token into ad-free time
 *   (the three token routes only need the DB binding, not Paystack)
 *   Settings: PAYSTACK_SECRET_KEY (secret), PAYSTACK_PLAN_CODE (optional),
 *             ADMIN_TOKEN (secret, falls back to STATS_TOKEN),
 *             PRICE_NGN (optional, default 2000), PRICE_NGN_YEAR (optional,
 *             default 20000), PAYSTACK_PLAN_CODE_YEAR (optional),
 *             DB (D1 binding)
 *
 * Analytics: only an anonymous random install id, app version, platform and
 * country are recorded. Subscriptions store the install id and the e-mail
 * the person typed at checkout.
 */

const FILES = {
  "fixtures.json": "fixtures.json",
  "highlights.json": "highlights.json",
  "movies.json": "movies.json",
  "tv.json": "tv.json",
  "ticker.json": "ticker.json",
};

const DEFAULT_RAW_BASE =
  "https://raw.githubusercontent.com/Deeprows/myflutter-app/main/assets/data";

const DATASET = "deeprowss_app";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET,HEAD,POST,OPTIONS",
  "access-control-allow-headers":
    "content-type, authorization, x-install-id, x-app-version, x-platform",
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: CORS,
      });
    }

    if (
      request.method !== "GET" &&
      request.method !== "HEAD" &&
      request.method !== "POST"
    ) {
      return json({ error: "method not allowed" }, 405);
    }

    // Health check.
    if (url.pathname === "/" || url.pathname === "/health") {
      return json({
        ok: true,
        service: "deeprowss-feed",
        // Setup check (no secret values): both should be true.
        analytics: Boolean(env.ANALYTICS),
        stats: Boolean(
          env.STATS_TOKEN && env.CF_ACCOUNT_ID && env.CF_API_TOKEN
        ),
        subscriptions: Boolean(env.DB && env.PAYSTACK_SECRET_KEY),
        // Ad-free tokens only need the D1 binding + an admin password.
        tokens: Boolean(env.DB && (env.ADMIN_TOKEN || env.STATS_TOKEN)),
      });
    }

    // Anonymous app-open analytics.
    if (
      url.pathname === "/analytics" &&
      request.method === "POST"
    ) {
      return analytics(request, env);
    }

    // Protected statistics page.
    if (
      url.pathname === "/stats" &&
      request.method === "GET"
    ) {
      return stats(url, env);
    }

    // Premium subscriptions.
    if (url.pathname.startsWith("/sub/")) {
      return subscriptions(request, env, url);
    }

    if (url.pathname.startsWith("/fan/")) return fanZone(request, env, url);

    // Feed routes.
    const m = /^\/feed\/([a-z0-9_-]+\.json)$/i.exec(url.pathname);

    if (m && FILES[m[1].toLowerCase()]) {
      return feed(
        request,
        env,
        ctx,
        m[1].toLowerCase()
      );
    }

    return json({
      error: "not found",
    }, 404);
  },
};

// ------------------------------------------------------------------ analytics

async function analytics(request, env) {
  try {
    if (!env.ANALYTICS) {
      return json({
        ok: false,
        error: "analytics not configured",
      }, 503);
    }

    const body = await request.json().catch(() => ({}));

    // Currently we only accept app_open.
    const event = String(
      body.event || ""
    ).slice(0, 32);

    if (event !== "app_open") {
      return json({
        ok: false,
        error: "unsupported event",
      }, 400);
    }

    const installId = String(
      body.installId || ""
    ).slice(0, 64);

    const appVersion = String(
      body.appVersion || "unknown"
    ).slice(0, 32);

    const platform = String(
      body.platform || "unknown"
    ).slice(0, 16);

    if (!installId) {
      return json({
        ok: false,
        error: "installId required",
      }, 400);
    }

    // The index is what Analytics Engine samples on. A constant index would
    // put every event in one bucket and undercount phones as traffic grows,
    // so use the (high-cardinality) install id.
    env.ANALYTICS.writeDataPoint({
      indexes: [installId],

      blobs: [
        "app_open",
        appVersion,
        platform,
        installId,
        request.cf?.country || "??",
        "app",
      ],

      doubles: [
        1,
        200,
      ],
    });

    return json({
      ok: true,
    });

  } catch (_) {
    // Analytics must never prevent the app from opening.
    return json({
      ok: false,
    }, 400);
  }
}

// ------------------------------------------------------------------ feed

async function feed(request, env, ctx, file) {
  // Short edge cache (default 10 s) so a new post shows up almost at once.
  // FEED_TTL=0 is allowed and turns the edge cache off completely.
  // The live-screen feeds (fixtures, ticker) are never edge-cached: every
  // open/refresh must see the file as it is right now.
  const noCache = file === "fixtures.json" || file === "ticker.json";
  const defaultTtl = noCache ? "0" : "10";
  const parsedTtl = parseInt(env.FEED_TTL ?? defaultTtl, 10);
  const ttl = noCache
    ? 0
    : clamp(
        Number.isNaN(parsedTtl) ? 10 : parsedTtl,
        0,
        600
      );

  const base = (
    env.GITHUB_RAW_BASE ||
    DEFAULT_RAW_BASE
  ).replace(/\/+$/, "");

  // raw.githubusercontent.com keeps every URL cached for ~5 minutes, which
  // is why new posts used to appear late. A unique query string makes GitHub
  // treat each Worker fetch as a new request, so it always returns the file
  // as it is right now.
  const origin = `${base}/${FILES[file]}?cb=${Date.now()}`;

  // Ignore query parameters for edge-cache purposes.
  const cacheKey = new Request(
    `https://feed-cache.invalid/${file}`
  );

  const cache = caches.default;

  let status = 200;
  let cacheState = "HIT";

  let response =
    ttl > 0
      ? await cache.match(cacheKey)
      : undefined;

  if (!response) {
    cacheState = "MISS";

    try {
      const upstream = await fetch(
        origin,
        {
          headers: {
            "user-agent":
              "deeprowss-feed-worker",
            accept:
              "application/json",
            "cache-control":
              "no-cache, no-store, max-age=0",
            pragma: "no-cache",
          },

          cf: {
            cacheTtl: 0,
            cacheEverything: false,
          },
        }
      );

      if (!upstream.ok) {
        status = 502;

        response = json({
          error:
            "origin returned " +
            upstream.status,
        }, 502);

      } else {
        const body =
          await upstream.text();

        response = new Response(
          body,
          {
            status: 200,

            headers: {
              "content-type":
                "application/json; charset=utf-8",

              "cache-control":
                ttl > 0 ? `public, max-age=${ttl}` : "no-store",
            },
          }
        );

        if (ttl > 0) {
          ctx.waitUntil(
            cache.put(
              cacheKey,
              response.clone()
            )
          );
        }
      }

    } catch (_) {
      status = 502;

      response = json({
        error: "origin unreachable",
      }, 502);
    }
  }

  // Existing feed analytics.
  record(
    env,
    request,
    file,
    status,
    cacheState
  );

  const out = new Response(
    response.body,
    response
  );

  for (
    const [k, v]
    of Object.entries(CORS)
  ) {
    out.headers.set(k, v);
  }

  out.headers.set(
    "cache-control",
    "no-cache"
  );

  out.headers.set(
    "x-feed-cache",
    cacheState
  );

  return out;
}

// ------------------------------------------------------------------ feed analytics

function record(
  env,
  request,
  file,
  status,
  cacheState
) {
  try {
    if (!env.ANALYTICS) {
      return;
    }

    const h = request.headers;

    const installId = (h.get("x-install-id") || "").slice(0, 64);

    env.ANALYTICS.writeDataPoint({
      indexes: [installId || file],

      blobs: [
        file,
        (
          h.get("x-app-version") ||
          "unknown"
        ).slice(0, 32),

        (
          h.get("x-platform") ||
          "unknown"
        ).slice(0, 16),

        (
          h.get("x-install-id") ||
          "unknown"
        ).slice(0, 64),

        request.cf?.country || "??",

        cacheState,
      ],

      doubles: [
        1,
        status,
      ],
    });

  } catch (_) {
    // Analytics must never break the feed.
  }
}

// ----------------------------------------------------------------- stats

async function stats(url, env) {
  if (
    !env.STATS_TOKEN ||
    url.searchParams.get("token") !==
      env.STATS_TOKEN
  ) {
    return new Response(
      "Not found",
      { status: 404 }
    );
  }

  if (
    !env.CF_ACCOUNT_ID ||
    !env.CF_API_TOKEN
  ) {
    return html(
      page(
        "Stats not configured",
        "<p>Add the secrets <b>CF_ACCOUNT_ID</b> and <b>CF_API_TOKEN</b> (token with <i>Account Analytics: Read</i>) to this Worker.</p>"
      )
    );
  }

  const t = DATASET;

  const q = {

    // Actual app opens.
    today:
      `SELECT COUNT(DISTINCT blob4) AS phones, ` +
      `SUM(_sample_interval) AS app_opens ` +
      `FROM ${t} ` +
      `WHERE blob1 = 'app_open' ` +
      `AND timestamp > NOW() - INTERVAL '1' DAY`,

    // Daily app usage.
    days:
      `SELECT ` +
      `toStartOfInterval(timestamp, INTERVAL '1' DAY) AS day, ` +
      `COUNT(DISTINCT blob4) AS phones, ` +
      `SUM(_sample_interval) AS app_opens ` +
      `FROM ${t} ` +
      `WHERE blob1 = 'app_open' ` +
      `AND timestamp > NOW() - INTERVAL '7' DAY ` +
      `GROUP BY day ` +
      `ORDER BY day DESC`,

    // Countries using the app.
    countries:
      `SELECT ` +
      `blob5 AS country, ` +
      `COUNT(DISTINCT blob4) AS phones, ` +
      `SUM(_sample_interval) AS app_opens ` +
      `FROM ${t} ` +
      `WHERE blob1 = 'app_open' ` +
      `AND timestamp > NOW() - INTERVAL '7' DAY ` +
      `GROUP BY country ` +
      `ORDER BY phones DESC ` +
      `LIMIT 15`,

    // App versions.
    versions:
      `SELECT ` +
      `blob2 AS version, ` +
      `COUNT(DISTINCT blob4) AS phones ` +
      `FROM ${t} ` +
      `WHERE blob1 = 'app_open' ` +
      `AND timestamp > NOW() - INTERVAL '7' DAY ` +
      `GROUP BY version ` +
      `ORDER BY phones DESC ` +
      `LIMIT 10`,

    // Existing feed traffic.
    files:
      `SELECT ` +
      `blob1 AS file, ` +
      `SUM(_sample_interval) AS requests ` +
      `FROM ${t} ` +
      `WHERE blob1 IN (` +
      `'fixtures.json',` +
      `'highlights.json',` +
      `'movies.json',` +
      `'tv.json',` +
      `'ticker.json'` +
      `) ` +
      `AND timestamp > NOW() - INTERVAL '1' DAY ` +
      `GROUP BY file ` +
      `ORDER BY requests DESC`,
  };

  try {
    const res = {};

    for (
      const [k, sql]
      of Object.entries(q)
    ) {
      res[k] =
        await runSql(
          env,
          sql
        );
    }

    const today =
      res.today[0] || {};

    const body = `

      <div class="grid">

        <div class="big">
          <span>
            ${num(today.phones)}
          </span>
          unique phones (24 h)
        </div>

        <div class="big">
          <span>
            ${num(today.app_opens)}
          </span>
          app opens (24 h)
        </div>

      </div>

      ${table(
        "Last 7 days",
        [
          "day",
          "phones",
          "app opens"
        ],
        res.days.map(
          (r) => [
            String(r.day)
              .slice(0, 10),

            num(r.phones),

            num(r.app_opens),
          ]
        )
      )}

      ${table(
        "Countries (7 days)",
        [
          "country",
          "phones",
          "app opens"
        ],
        res.countries.map(
          (r) => [
            r.country,
            num(r.phones),
            num(r.app_opens),
          ]
        )
      )}

      ${table(
        "App versions (7 days)",
        [
          "version",
          "phones"
        ],
        res.versions.map(
          (r) => [
            r.version,
            num(r.phones),
          ]
        )
      )}

      ${table(
        "Feed files (24 h)",
        [
          "file",
          "requests"
        ],
        res.files.map(
          (r) => [
            r.file,
            num(r.requests),
          ]
        )
      )}

      <p class="muted">
        "Phones" = distinct anonymous
        install ids. App opens are recorded
        separately from feed requests.
        Data appears a minute or two after use.
      </p>
    `;

    return html(
      page(
        "Deeprowss usage",
        body
      )
    );

  } catch (e) {

    return html(
      page(
        "Stats error",
        `<p>${esc(
          String(
            e.message || e
          )
        )}</p>`
      ),
      500
    );
  }
}

// ------------------------------------------------------------------ SQL

async function runSql(
  env,
  sql
) {
  const r = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${env.CF_ACCOUNT_ID}/analytics_engine/sql`,
    {
      method: "POST",

      headers: {
        authorization:
          `Bearer ${env.CF_API_TOKEN}`,
      },

      body:
        sql +
        " FORMAT JSON",
    }
  );

  const text =
    await r.text();

  if (!r.ok) {
    throw new Error(
      `Analytics query failed (${r.status}): ${text.slice(0, 300)}`
    );
  }

  return (
    JSON.parse(text).data ||
    []
  );
}

// --------------------------------------------------------------- helpers

const clamp = (
  n,
  lo,
  hi
) =>
  Math.min(
    hi,
    Math.max(lo, n)
  );

const num = (v) =>
  Number(v || 0)
    .toLocaleString("en-US");

const esc = (s) =>
  String(s).replace(
    /[&<>"']/g,
    (c) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      }[c])
  );

function json(
  obj,
  status = 200
) {
  return new Response(
    JSON.stringify(obj),
    {
      status,

      headers: {
        "content-type":
          "application/json; charset=utf-8",

        ...CORS,
      },
    }
  );
}

function html(
  body,
  status = 200
) {
  return new Response(
    body,
    {
      status,

      headers: {
        "content-type":
          "text/html; charset=utf-8",

        "cache-control":
          "no-store",

        "x-robots-tag":
          "noindex",
      },
    }
  );
}

function table(
  title,
  head,
  rows
) {
  if (!rows.length) {
    return `
      <h2>${esc(title)}</h2>
      <p class="muted">
        No data yet.
      </p>
    `;
  }

  return `
    <h2>${esc(title)}</h2>

    <table>
      <tr>
        ${head
          .map(
            (h) =>
              `<th>${esc(h)}</th>`
          )
          .join("")}
      </tr>

      ${
        rows
          .map(
            (r) =>
              `<tr>${
                r
                  .map(
                    (c) =>
                      `<td>${esc(c)}</td>`
                  )
                  .join("")
              }</tr>`
          )
          .join("")
      }

    </table>
  `;
}

function page(
  title,
  body
) {
  return `<!doctype html>
<html>
<head>

<meta charset="utf-8">

<meta
  name="viewport"
  content="width=device-width,initial-scale=1"
>

<title>
  ${esc(title)}
</title>

<style>

body{
  margin:0;
  padding:18px;
  background:#0b0f17;
  color:#e8ecf3;
  font:15px/1.45 system-ui,sans-serif
}

h1{
  font-size:20px;
  margin:0 0 14px
}

h2{
  font-size:15px;
  margin:22px 0 8px;
  color:#9fb0c8
}

.grid{
  display:flex;
  gap:10px
}

.big{
  flex:1;
  background:#131a26;
  border:1px solid #243047;
  border-radius:14px;
  padding:14px;
  color:#9fb0c8;
  font-size:12.5px
}

.big span{
  display:block;
  font-size:28px;
  font-weight:800;
  color:#fff
}

table{
  width:100%;
  border-collapse:collapse;
  background:#131a26;
  border-radius:12px;
  overflow:hidden
}

th,td{
  padding:8px 10px;
  text-align:left;
  border-bottom:1px solid #1d2739
}

th{
  color:#9fb0c8;
  font-weight:600;
  font-size:12.5px
}

.muted{
  color:#7d8ca3;
  font-size:12.5px
}

</style>

</head>

<body>

<h1>
  ${esc(title)}
</h1>

${body}

</body>
</html>`;
}

// -------------------------------------------------------------- subscriptions
//
// Premium = no "Support" pop-ups. The app only ever asks THIS Worker whether
// an install is premium; the Paystack secret key never leaves the Worker.
//
//   charge.success (webhook) or /sub/verify  ->  payments (one row per
//   Paystack reference, so a payment can never be counted twice)  ->  subs
//   (one row per install id with the expiry time).

const DAY_MS = 86400000;
const PERIOD_DAYS = 31; // one paid month, with a day of slack for renewals
const YEAR_DAYS = 366; // one paid year, with a day of slack
const ID_RE = /^[a-z0-9]{16,64}$/i;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

let schemaReady = false;

const priceNgn = (env) =>
  Math.max(1, parseInt(env.PRICE_NGN ?? "2000", 10) || 2000);

// Yearly price (default 20,000 = two months free). Change PRICE_NGN_YEAR.
const priceYearNgn = (env) =>
  Math.max(1, parseInt(env.PRICE_NGN_YEAR ?? "20000", 10) || 20000);

/** "year" or "month". Renewals carry no metadata, so fall back to the amount. */
function periodOf(env, tx) {
  const p = String(tx?.metadata?.period || "");
  if (p === "year" || p === "month") return p;
  return Number(tx?.amount) >= priceYearNgn(env) * 100 ? "year" : "month";
}

async function ensureSchema(env) {
  if (schemaReady) return;
  await env.DB.batch([
    env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS subs (install_id TEXT PRIMARY KEY, email TEXT, expires_at INTEGER NOT NULL DEFAULT 0, source TEXT, updated_at INTEGER NOT NULL DEFAULT 0)"
    ),
    env.DB.prepare(
      "CREATE INDEX IF NOT EXISTS subs_email ON subs (email)"
    ),
    env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS payments (reference TEXT PRIMARY KEY, install_id TEXT, email TEXT, amount INTEGER, created_at INTEGER NOT NULL DEFAULT 0)"
    ),
    env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS tokens (token TEXT PRIMARY KEY, days INTEGER NOT NULL, bound_to TEXT, note TEXT, created_at INTEGER NOT NULL DEFAULT 0, redeemed_by TEXT, redeemed_at INTEGER)"
    ),
    env.DB.prepare(
      "CREATE TABLE IF NOT EXISTS token_requests (install_id TEXT PRIMARY KEY, contact TEXT, created_at INTEGER NOT NULL DEFAULT 0)"
    ),
  ]);
  schemaReady = true;
}

async function subscriptions(request, env, url) {
  const path = url.pathname;

  // The "payment finished" page Paystack sends the person back to. The app's
  // checkout window notices this address and closes itself.
  if (path === "/sub/done") {
    return new Response(
      `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><body style="font-family:sans-serif;background:#080b10;color:#fff;text-align:center;padding:48px 20px"><h2>Payment received</h2><p>You can go back to the Deeprowss app.</p>`,
      { headers: { "content-type": "text/html; charset=utf-8" } }
    );
  }

  if (path === "/sub/config" && request.method === "GET") {
    return subConfig(url, env);
  }

  // Status, the admin page and the token routes only need the database;
  // everything else also needs the Paystack key.
  const dbOnly =
    path === "/sub/status" ||
    path === "/sub/admin" ||
    path.startsWith("/sub/token/");
  if (!env.DB || (!env.PAYSTACK_SECRET_KEY && !dbOnly)) {
    return json({ error: "subscriptions are not set up on the server" }, 503);
  }

  try {
    await ensureSchema(env);

    if (path === "/sub/status" && request.method === "GET") {
      return subStatus(url, env);
    }
    if (path === "/sub/start" && request.method === "POST") {
      return subStart(request, env, url);
    }
    if (path === "/sub/verify" && request.method === "GET") {
      return subVerify(url, env);
    }
    if (path === "/sub/webhook" && request.method === "POST") {
      return subWebhook(request, env);
    }
    if (path === "/sub/restore" && request.method === "POST") {
      return subRestore(request, env);
    }
    if (path === "/sub/token/request" && request.method === "POST") {
      return tokenRequest(request, env);
    }
    if (path === "/sub/token/mine" && request.method === "GET") {
      return tokenMine(url, env);
    }
    if (path === "/sub/token/redeem" && request.method === "POST") {
      return tokenRedeem(request, env);
    }
    if (path === "/sub/admin") {
      return subAdmin(request, env, url);
    }
  } catch (e) {
    console.error("subscription error", e && e.message);
    return json({ error: "server error" }, 500);
  }

  return json({ error: "not found" }, 404);
}

// ---- price + local currency ------------------------------------------------

async function ngnRates() {
  const key = new Request("https://rates.internal/ngn");
  let res = await caches.default.match(key);
  if (!res) {
    const r = await fetch("https://open.er-api.com/v6/latest/NGN");
    if (!r.ok) return null;
    const body = await r.json();
    if (!body || !body.rates) return null;
    res = new Response(JSON.stringify(body.rates), {
      headers: { "cache-control": "public, max-age=21600" },
    });
    await caches.default.put(key, res.clone());
  }
  return res.json();
}

function money(amount, currency) {
  try {
    return new Intl.NumberFormat("en", {
      style: "currency",
      currency,
      currencyDisplay: "narrowSymbol",
    }).format(amount);
  } catch {
    return `${currency} ${amount.toFixed(2)}`;
  }
}

async function subConfig(url, env) {
  const price = priceNgn(env);
  const yearPrice = priceYearNgn(env);
  const out = {
    price_ngn: price,
    price_display: money(price, "NGN").replace(/\.00$/, ""),
    year_price_ngn: yearPrice,
    year_price_display: money(yearPrice, "NGN").replace(/\.00$/, ""),
    recurring: Boolean(env.PAYSTACK_PLAN_CODE),
    recurring_year: Boolean(env.PAYSTACK_PLAN_CODE_YEAR),
    available: Boolean(env.DB && env.PAYSTACK_SECRET_KEY),
    currency: "NGN",
    local_display: null,
    year_local_display: null,
  };

  const cur = (url.searchParams.get("cur") || "").toUpperCase();
  if (/^[A-Z]{3}$/.test(cur) && cur !== "NGN") {
    try {
      const rates = await ngnRates();
      const rate = rates && Number(rates[cur]);
      if (rate > 0) {
        // Round up to a whole cent so the shown amount never looks cheaper
        // than what the bank will really take.
        const local = Math.ceil(price * rate * 100) / 100;
        const localYear = Math.ceil(yearPrice * rate * 100) / 100;
        out.currency = cur;
        out.local_amount = local;
        out.local_display = money(local, cur);
        out.year_local_display = money(localYear, cur);
      }
    } catch {
      // No rates: the app simply shows the naira price.
    }
  }
  return json(out);
}

// ---- Paystack --------------------------------------------------------------

async function paystack(env, path, init = {}) {
  const r = await fetch(`https://api.paystack.co${path}`, {
    ...init,
    headers: {
      authorization: `Bearer ${env.PAYSTACK_SECRET_KEY}`,
      "content-type": "application/json",
    },
  });
  let body = null;
  try {
    body = await r.json();
  } catch {}
  return { ok: r.ok && body && body.status === true, body };
}

async function hmacHex(secret, text) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(text)
  );
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ---- entitlement -----------------------------------------------------------

async function expiryOf(env, installId) {
  const row = await env.DB.prepare(
    "SELECT expires_at FROM subs WHERE install_id = ?"
  )
    .bind(installId)
    .first();
  return row ? Number(row.expires_at) || 0 : 0;
}

/** Adds [days] on top of whatever time is left (never loses paid time). */
async function addDays(env, installId, { email, source, days }) {
  const now = Date.now();
  const left = await expiryOf(env, installId);
  const expires = Math.max(now, left) + days * DAY_MS;
  await env.DB.prepare(
    "INSERT INTO subs (install_id, email, expires_at, source, updated_at) VALUES (?, ?, ?, ?, ?) " +
      "ON CONFLICT(install_id) DO UPDATE SET expires_at = excluded.expires_at, " +
      "email = COALESCE(excluded.email, subs.email), source = excluded.source, updated_at = excluded.updated_at"
  )
    .bind(installId, email || null, expires, source, now)
    .run();
  return expires;
}

/** Turns a successful Paystack transaction into premium time, once. */
async function settle(env, tx) {
  if (!tx || tx.status !== "success") return null;
  const period = periodOf(env, tx);
  const need = (period === "year" ? priceYearNgn(env) : priceNgn(env)) * 100;
  if (tx.currency !== "NGN" || Number(tx.amount) < need) {
    return null;
  }
  const reference = String(tx.reference || "");
  if (!reference) return null;

  const email = String(tx.customer?.email || "").toLowerCase() || null;
  let installId = tx.metadata?.install_id;
  if (!ID_RE.test(String(installId || ""))) {
    // An automatic renewal: Paystack does not repeat our metadata, so find
    // the install by the customer's e-mail.
    const row = email
      ? await env.DB.prepare(
          "SELECT install_id FROM subs WHERE email = ? ORDER BY updated_at DESC LIMIT 1"
        )
          .bind(email)
          .first()
      : null;
    installId = row?.install_id;
  }
  if (!installId) return null;

  const ins = await env.DB.prepare(
    "INSERT OR IGNORE INTO payments (reference, install_id, email, amount, created_at) VALUES (?, ?, ?, ?, ?)"
  )
    .bind(reference, installId, email, Number(tx.amount), Date.now())
    .run();

  if (ins.meta && ins.meta.changes === 0) {
    // Already counted (webhook and verify both arrive for one payment).
    return { installId, expires: await expiryOf(env, installId) };
  }
  const expires = await addDays(env, installId, {
    email,
    source: "paystack",
    days: period === "year" ? YEAR_DAYS : PERIOD_DAYS,
  });
  return { installId, expires };
}

// ---- routes ----------------------------------------------------------------

async function subStatus(url, env) {
  const id = url.searchParams.get("install") || "";
  if (!ID_RE.test(id)) return json({ error: "bad install id" }, 400);
  const expires = await expiryOf(env, id);
  return json({ active: expires > Date.now(), expires_at: expires });
}

async function subStart(request, env, url) {
  let b;
  try {
    b = await request.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const installId = String(b.install_id || "");
  const email = String(b.email || "").trim().toLowerCase();
  if (!ID_RE.test(installId)) return json({ error: "bad install id" }, 400);
  if (!EMAIL_RE.test(email)) {
    return json({ error: "Enter a valid e-mail address" }, 400);
  }

  const period = b.period === "year" ? "year" : "month";
  const allChannels = ["card", "ussd", "bank_transfer", "bank", "mobile_money"];
  const channels = Array.isArray(b.channels)
    ? b.channels.filter((c) => allChannels.includes(c))
    : [];

  const reference =
    "DR" +
    Date.now().toString(36) +
    crypto.randomUUID().replace(/-/g, "").slice(0, 10);
  const body = {
    email,
    amount: (period === "year" ? priceYearNgn(env) : priceNgn(env)) * 100, // kobo
    currency: "NGN",
    reference,
    callback_url: `${url.origin}/sub/done`,
    metadata: { install_id: installId, app: "deeprowss", period },
  };
  // Open Paystack straight on the method the person picked (card / USSD / ...).
  if (channels.length) body.channels = channels;
  // A plan makes the card renew by itself every month (card payments only).
  const planCode =
    period === "year" ? env.PAYSTACK_PLAN_CODE_YEAR : env.PAYSTACK_PLAN_CODE;
  if (b.recurring && planCode) body.plan = planCode;

  const r = await paystack(env, "/transaction/initialize", {
    method: "POST",
    body: JSON.stringify(body),
  });
  if (!r.ok || !r.body.data?.authorization_url) {
    return json(
      { error: r.body?.message || "Could not start the payment" },
      502
    );
  }

  // Remember the e-mail now so a renewal can find this install later.
  await env.DB.prepare(
    "INSERT INTO subs (install_id, email, expires_at, source, updated_at) VALUES (?, ?, 0, 'pending', ?) " +
      "ON CONFLICT(install_id) DO UPDATE SET email = excluded.email"
  )
    .bind(installId, email, Date.now())
    .run();

  return json({
    authorization_url: r.body.data.authorization_url,
    reference,
  });
}

async function subVerify(url, env) {
  const reference = url.searchParams.get("reference") || "";
  if (!/^[A-Za-z0-9._-]{6,80}$/.test(reference)) {
    return json({ error: "bad reference" }, 400);
  }
  const r = await paystack(
    env,
    `/transaction/verify/${encodeURIComponent(reference)}`
  );
  if (!r.ok) return json({ status: "failed" });
  const tx = r.body.data;
  if (tx.status !== "success") {
    const pending = ["pending", "ongoing", "processing", "queued"].includes(
      tx.status
    );
    return json({ status: pending ? "pending" : "failed" });
  }
  const done = await settle(env, tx);
  if (!done) return json({ status: "failed" });
  return json({
    status: "success",
    active: done.expires > Date.now(),
    expires_at: done.expires,
    install_id: done.installId,
  });
}

async function subWebhook(request, env) {
  const raw = await request.text();
  const sig = request.headers.get("x-paystack-signature") || "";
  if (!sig || sig !== (await hmacHex(env.PAYSTACK_SECRET_KEY, raw))) {
    return json({ error: "bad signature" }, 401);
  }
  let ev;
  try {
    ev = JSON.parse(raw);
  } catch {
    return json({ ok: true });
  }
  if (ev.event === "charge.success") await settle(env, ev.data);
  return json({ ok: true });
}

/** New phone: prove the payment with its e-mail + Paystack reference. */
async function subRestore(request, env) {
  let b;
  try {
    b = await request.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const installId = String(b.install_id || "");
  const email = String(b.email || "").trim().toLowerCase();
  const reference = String(b.reference || "").trim();
  if (!ID_RE.test(installId) || !EMAIL_RE.test(email) || !reference) {
    return json({ error: "Enter your e-mail and payment reference" }, 400);
  }
  const r = await paystack(
    env,
    `/transaction/verify/${encodeURIComponent(reference)}`
  );
  const tx = r.ok ? r.body.data : null;
  if (
    !tx ||
    tx.status !== "success" ||
    String(tx.customer?.email || "").toLowerCase() !== email
  ) {
    return json({ error: "No payment found for that e-mail and reference" }, 404);
  }
  const row = await env.DB.prepare(
    "SELECT MAX(expires_at) AS e FROM subs WHERE email = ?"
  )
    .bind(email)
    .first();
  const expires = Number(row?.e) || 0;
  if (expires <= Date.now()) {
    return json({ error: "That subscription has expired" }, 404);
  }
  await env.DB.prepare(
    "INSERT INTO subs (install_id, email, expires_at, source, updated_at) VALUES (?, ?, ?, 'restored', ?) " +
      "ON CONFLICT(install_id) DO UPDATE SET expires_at = MAX(subs.expires_at, excluded.expires_at), email = excluded.email, source = 'restored', updated_at = excluded.updated_at"
  )
    .bind(installId, email, expires, Date.now())
    .run();
  return json({ ok: true, active: true, expires_at: expires });
}

// ---- ad-free tokens ---------------------------------------------------------
//
// A phone asks for a token (/sub/token/request). You see the request on the
// admin page and press "Create token" (or make tokens in advance). The phone
// finds the token by itself (/sub/token/mine) or the person types it in; either
// way /sub/token/redeem turns it into ad-free days on that phone's install id.
// A token works once. A token made from a request only works on that phone.

const TOKEN_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0 O 1 I
const TOKEN_LEN = 12;
const MAX_TOKEN_DAYS = 3650;

function makeToken() {
  const bytes = new Uint8Array(TOKEN_LEN);
  crypto.getRandomValues(bytes);
  // 32 symbols and 256 byte values: "& 31" has no bias.
  return Array.from(bytes, (b) => TOKEN_ALPHABET[b & 31]).join("");
}

/** "abcd-efgh ijkl" -> "ABCDEFGHIJKL" */
const normToken = (t) =>
  String(t || "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");

/** "ABCDEFGHJKLM" -> "ABCD-EFGH-JKLM" */
const showToken = (t) => String(t).replace(/(.{4})(?=.)/g, "$1-");

async function mintTokens(env, { days, count = 1, boundTo = null, note = "" }) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const token = makeToken();
    await env.DB.prepare(
      "INSERT INTO tokens (token, days, bound_to, note, created_at) VALUES (?, ?, ?, ?, ?)"
    )
      .bind(token, days, boundTo, note || null, Date.now())
      .run();
    out.push(token);
  }
  return out;
}

async function tokenRequest(request, env) {
  let b;
  try {
    b = await request.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const installId = String(b.install_id || "");
  if (!ID_RE.test(installId)) return json({ error: "bad install id" }, 400);
  const contact = String(b.contact || "").trim().slice(0, 80);

  if ((await expiryOf(env, installId)) > Date.now()) {
    return json({ ok: true, state: "active" });
  }
  await env.DB.prepare(
    "INSERT INTO token_requests (install_id, contact, created_at) VALUES (?, ?, ?) " +
      "ON CONFLICT(install_id) DO UPDATE SET contact = COALESCE(NULLIF(excluded.contact, ''), token_requests.contact), created_at = excluded.created_at"
  )
    .bind(installId, contact, Date.now())
    .run();
  return json({ ok: true, state: "pending" });
}

/** Has the request been answered? Returns the token made for this phone. */
async function tokenMine(url, env) {
  const id = url.searchParams.get("install") || "";
  if (!ID_RE.test(id)) return json({ error: "bad install id" }, 400);
  const expires = await expiryOf(env, id);
  if (expires > Date.now()) {
    return json({ state: "active", expires_at: expires });
  }
  const t = await env.DB.prepare(
    "SELECT token, days FROM tokens WHERE bound_to = ? AND redeemed_by IS NULL ORDER BY created_at DESC LIMIT 1"
  )
    .bind(id)
    .first();
  if (t) return json({ state: "ready", token: showToken(t.token), days: t.days });
  const r = await env.DB.prepare(
    "SELECT 1 AS x FROM token_requests WHERE install_id = ?"
  )
    .bind(id)
    .first();
  return json({ state: r ? "pending" : "none" });
}

async function tokenRedeem(request, env) {
  let b;
  try {
    b = await request.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const installId = String(b.install_id || "");
  const token = normToken(b.token);
  if (!ID_RE.test(installId)) return json({ error: "bad install id" }, 400);
  if (token.length !== TOKEN_LEN) {
    return json({ error: "Enter the token exactly as you received it" }, 400);
  }

  const row = await env.DB.prepare(
    "SELECT token, days, bound_to, redeemed_by FROM tokens WHERE token = ?"
  )
    .bind(token)
    .first();
  if (!row) return json({ error: "That token is not valid" }, 404);

  if (row.redeemed_by) {
    if (row.redeemed_by === installId) {
      // Same phone pressing the button twice: just report the time it has.
      const e = await expiryOf(env, installId);
      return json({ ok: true, active: e > Date.now(), expires_at: e });
    }
    return json({ error: "That token has already been used" }, 409);
  }
  if (row.bound_to && row.bound_to !== installId) {
    return json({ error: "That token was made for another phone" }, 403);
  }

  // Claim it first (only one phone can win), then add the time.
  const claim = await env.DB.prepare(
    "UPDATE tokens SET redeemed_by = ?, redeemed_at = ? WHERE token = ? AND redeemed_by IS NULL"
  )
    .bind(installId, Date.now(), token)
    .run();
  if (Number(claim?.meta?.changes) !== 1) {
    return json({ error: "That token has already been used" }, 409);
  }
  const expires = await addDays(env, installId, {
    email: null,
    source: "token",
    days: Number(row.days),
  });
  await env.DB.prepare("DELETE FROM token_requests WHERE install_id = ?")
    .bind(installId)
    .run();
  return json({ ok: true, active: true, expires_at: expires });
}

/**
 * Phone-friendly admin page:
 *   /sub/admin?token=<ADMIN_TOKEN>
 *  - Token requests: phones that pressed "Request token". Choose the days and
 *    press "Create token"; the phone receives it by itself (or you send it).
 *  - Make tokens in advance (for people you chat with on WhatsApp/Telegram).
 *  - Grant days straight to an ID (0 days switches someone off).
 */
async function subAdmin(request, env, url) {
  const secret = env.ADMIN_TOKEN || env.STATS_TOKEN;
  const form = request.method === "POST" ? await request.formData() : null;
  const token = form ? form.get("token") : url.searchParams.get("token");
  if (!secret || token !== secret) return json({ error: "forbidden" }, 403);

  let note = "";
  let made = [];
  if (form) {
    const action = String(form.get("action") || "grant");
    const id = String(form.get("install_id") || "").trim();
    const days = parseInt(String(form.get("days") || ""), 10);
    const daysOk = days >= 0 && days <= MAX_TOKEN_DAYS;

    if (action === "mint") {
      const count = Math.min(
        20,
        Math.max(1, parseInt(String(form.get("count") || "1"), 10) || 1)
      );
      const label = String(form.get("note") || "").trim().slice(0, 60);
      if (!(days >= 1 && days <= MAX_TOKEN_DAYS)) {
        note = "Days must be 1-3650.";
      } else {
        made = await mintTokens(env, { days, count, note: label });
        note = `${made.length} token(s) made, ${days} day(s) each. Each works once, on any phone.`;
      }
    } else if (action === "answer") {
      if (!ID_RE.test(id) || !(days >= 1 && days <= MAX_TOKEN_DAYS)) {
        note = "Check the ID and the days (1-3650).";
      } else {
        const req = await env.DB.prepare(
          "SELECT contact FROM token_requests WHERE install_id = ?"
        )
          .bind(id)
          .first();
        made = await mintTokens(env, {
          days,
          boundTo: id,
          note: req?.contact || "",
        });
        // Answered: take it out of the waiting list. The phone now finds
        // the token through /sub/token/mine.
        await env.DB.prepare("DELETE FROM token_requests WHERE install_id = ?")
          .bind(id)
          .run();
        note = `Token made for ${id.slice(0, 12)}… (${days} days). The phone shows it by itself; you can also send it.`;
      }
    } else if (action === "dismiss") {
      await env.DB.prepare("DELETE FROM token_requests WHERE install_id = ?")
        .bind(id)
        .run();
      note = "Request removed.";
    } else if (!ID_RE.test(id) || !daysOk) {
      note = "Check the ID (letters/numbers only) and the days (0-3650).";
    } else if (days === 0) {
      await env.DB.prepare(
        "INSERT INTO subs (install_id, expires_at, source, updated_at) VALUES (?, 0, 'revoked', ?) " +
          "ON CONFLICT(install_id) DO UPDATE SET expires_at = 0, source = 'revoked', updated_at = excluded.updated_at"
      )
        .bind(id, Date.now())
        .run();
      note = `Premium switched off for ${id}`;
    } else {
      const e = await addDays(env, id, { email: null, source: "manual", days });
      note = `Premium until ${new Date(e).toISOString().slice(0, 10)} for ${id}`;
    }
  }

  const day = (ms) => new Date(Number(ms)).toISOString().slice(0, 10);
  const tk = esc(String(token));
  const btn = "padding:9px 12px;font-size:15px";
  const box = "width:100%;padding:12px;box-sizing:border-box";

  // Digits only go into the link, so nothing typed by a phone can break out.
  const waLink = (c) => {
    const d = String(c || "").replace(/\D/g, "");
    return d.length >= 7 && d.length <= 15
      ? ` &middot; <a href="https://wa.me/${d}" style="color:#22e07a">Open WhatsApp</a>`
      : "";
  };

  const reqs = (
    await env.DB.prepare(
      "SELECT install_id, contact, created_at FROM token_requests ORDER BY created_at DESC LIMIT 30"
    ).all()
  ).results || [];
  const reqHtml = reqs.length
    ? reqs
        .map(
          (r) => `<form method="post" style="background:#101722;padding:10px;border-radius:8px;margin:8px 0">
<input type="hidden" name="token" value="${tk}"><input type="hidden" name="install_id" value="${esc(r.install_id)}">
<div style="font-size:12.5px;margin-bottom:6px">${esc(String(r.install_id).slice(0, 12))}… &middot; ${esc(day(r.created_at))}${r.contact ? ` &middot; <b>${esc(r.contact)}</b>` : ""}${waLink(r.contact)}</div>
<input name="days" type="number" value="30" style="width:80px;padding:9px">
<button name="action" value="answer" style="${btn}">Create token</button>
<button name="action" value="dismiss" style="${btn}">Dismiss</button>
</form>`
        )
        .join("")
    : `<p style="color:#8d99ab;font-size:13px">No requests waiting.</p>`;

  const unused = (
    await env.DB.prepare(
      "SELECT token, days, bound_to, note FROM tokens WHERE redeemed_by IS NULL ORDER BY created_at DESC LIMIT 25"
    ).all()
  ).results || [];
  const unusedHtml = unused
    .map(
      (r) =>
        `<tr><td style="font-family:monospace">${esc(showToken(r.token))}</td><td>${esc(r.days)}d</td><td>${r.bound_to ? esc(String(r.bound_to).slice(0, 8)) + "…" : "any"}</td><td>${esc(r.note || "")}</td></tr>`
    )
    .join("");

  const rows = await env.DB.prepare(
    "SELECT install_id, email, expires_at, source FROM subs WHERE expires_at > 0 ORDER BY updated_at DESC LIMIT 25"
  ).all();
  const list = (rows.results || [])
    .map(
      (r) =>
        `<tr><td>${esc(String(r.install_id).slice(0, 12))}…</td><td>${esc(r.source)}</td><td>${esc(day(r.expires_at))}</td><td>${esc(r.email || "")}</td></tr>`
    )
    .join("");

  const madeHtml = made.length
    ? `<div style="background:#12301f;padding:10px;border-radius:8px;font-family:monospace;font-size:17px;line-height:1.7">${made
        .map((t) => esc(showToken(t)))
        .join("<br>")}</div>`
    : "";

  return html(
    `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Ad-free admin</title>
<body style="font-family:sans-serif;background:#080b10;color:#e8edf5;padding:18px;max-width:560px;margin:auto">
<h2>Ad-free admin</h2>
${note ? `<p style="background:#16202e;padding:10px;border-radius:8px">${esc(note)}</p>` : ""}
${madeHtml}
<h3>Token requests</h3>
${reqHtml}
<h3>Make tokens</h3>
<form method="post">
<input type="hidden" name="token" value="${tk}"><input type="hidden" name="action" value="mint">
<p><input name="days" type="number" value="30" placeholder="Days" style="${box}"></p>
<p><input name="count" type="number" value="1" placeholder="How many (1-20)" style="${box}"></p>
<p><input name="note" placeholder="Note (optional, e.g. a name)" style="${box}"></p>
<p><button style="${box};font-size:16px">Make token(s)</button></p>
</form>
<h3>Grant days to an ID</h3>
<form method="post">
<input type="hidden" name="token" value="${tk}"><input type="hidden" name="action" value="grant">
<p><input name="install_id" placeholder="Paste the person's ID" style="${box}"></p>
<p><input name="days" type="number" value="30" style="${box}"></p>
<p><button style="${box};font-size:16px">Grant days (0 = switch off)</button></p>
</form>
<h3>Unused tokens</h3>
<table style="width:100%;font-size:12.5px"><tr><th align=left>Token<th align=left>Days<th align=left>For<th align=left>Note</tr>${unusedHtml}</table>
<h3>Ad-free phones</h3>
<table style="width:100%;font-size:12.5px"><tr><th align=left>ID<th align=left>Source<th align=left>Until<th align=left>E-mail</tr>${list}</table>
</body>`
  );
}

// Fan Zone: all scores, cutoffs and rankings are controlled by the server.
export function fanKey(f) {
  return `${f.id}|${new Date(f.kickoff).getTime()}`;
}
export function fanWeek(now = new Date()) {
  const d = new Date(now);
  d.setUTCHours(0, 0, 0, 0);
  d.setUTCDate(d.getUTCDate() - (d.getUTCDay() + 6) % 7);
  return d.getTime();
}
export function fanPoints(h, a, rh, ra) {
  return h === rh && a === ra ? 3 : Math.sign(h - a) === Math.sign(rh - ra) ? 1 : 0;
}
const FAN_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS fan_users (id TEXT PRIMARY KEY, name TEXT NOT NULL, last_post INTEGER NOT NULL DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS fan_picks (user_id TEXT NOT NULL, match_key TEXT NOT NULL, title TEXT NOT NULL, kickoff INTEGER NOT NULL, home INTEGER NOT NULL, away INTEGER NOT NULL, PRIMARY KEY(user_id, match_key))`,
  `CREATE TABLE IF NOT EXISTS fan_results (match_key TEXT PRIMARY KEY, home INTEGER NOT NULL, away INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS fan_messages (id TEXT PRIMARY KEY, room TEXT NOT NULL, user_id TEXT NOT NULL, text TEXT NOT NULL, at INTEGER NOT NULL, hidden INTEGER NOT NULL DEFAULT 0)`,
  `CREATE INDEX IF NOT EXISTS fan_room_time ON fan_messages(room, at)`,
  `CREATE TABLE IF NOT EXISTS fan_reports (message_id TEXT NOT NULL, user_id TEXT NOT NULL, reason TEXT NOT NULL, PRIMARY KEY(message_id,user_id))`,
  `CREATE TABLE IF NOT EXISTS fan_posts (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, text TEXT NOT NULL, image_key TEXT NOT NULL DEFAULT '', at INTEGER NOT NULL, hidden INTEGER NOT NULL DEFAULT 0)`,
  `CREATE INDEX IF NOT EXISTS fan_post_time ON fan_posts(at DESC,id DESC)`,
  `CREATE TABLE IF NOT EXISTS fan_post_reports (post_id TEXT NOT NULL, user_id TEXT NOT NULL, reason TEXT NOT NULL, PRIMARY KEY(post_id,user_id))`,
  `CREATE TABLE IF NOT EXISTS fan_accounts (id TEXT PRIMARY KEY, google_sub TEXT NOT NULL UNIQUE, email TEXT NOT NULL, name TEXT NOT NULL, photo TEXT NOT NULL, created_at INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS fan_legacy_claims (legacy_id TEXT PRIMARY KEY, account_id TEXT NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS fan_limits (bucket TEXT PRIMARY KEY, count INTEGER NOT NULL)`
];
const fanReady = new WeakMap();
async function fanInit(db) {
  if (!fanReady.has(db)) {
    fanReady.set(db, db.batch(FAN_SCHEMA.map(sql => db.prepare(sql))).catch(e => {
      fanReady.delete(db); throw e;
    }));
  }
  await fanReady.get(db);
}
async function fanHash(s) {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map(n => n.toString(16).padStart(2, '0')).join('');
}
async function fanFixtures(env) {
  const base = (env.GITHUB_RAW_BASE || DEFAULT_RAW_BASE).replace(/\/$/, '');
  const res = await fetch(`${base}/fixtures.json`, {signal: AbortSignal.timeout(10000), cache: 'no-store'});
  if (!res.ok) throw new Error('Fixtures unavailable. Try again shortly.');
  const raw = await res.json();
  const list = Array.isArray(raw) ? raw : raw.fixtures;
  if (!Array.isArray(list)) throw new Error('Fixtures unavailable.');
  return list.map(f => {
    let k = String(f.kickoff || '');
    if (!/(Z|[+-]\d{2}:?\d{2})$/i.test(k)) k += '+01:00';
    return {...f, kickoff:k};
  }).filter(f => f.id && Number.isFinite(new Date(f.kickoff).getTime()));
}
async function fanZone(request, env, url) {
  const fail = (message, status = 400) => json({error:message}, status);
  if (!env.DB) return fail('Fan Zone needs the Worker DB binding. See FAN_ZONE_SETUP.md.', 503);
  try {
    await fanInit(env.DB);
    const db = env.DB;
    if(url.pathname==='/fan/auth')return await fanAccountAuth(request,env);
    if(request.method==='GET' && url.pathname.startsWith('/fan/image/')) {
      const imageId=url.pathname.slice('/fan/image/'.length);
      if(!/^[a-f0-9-]{36}$/.test(imageId))return fail('Image not found',404);
      const post=await db.prepare('SELECT image_key FROM fan_posts WHERE id=? AND hidden=0').bind(imageId).first();
      if(!post?.image_key || !env.FAN_MEDIA)return fail('Image not found',404);
      const image=await env.FAN_MEDIA.get(post.image_key);
      if(!image)return fail('Image not found',404);
      const headers=new Headers(CORS);
      image.writeHttpMetadata(headers);
      headers.set('cache-control','no-store');
      headers.set('x-content-type-options','nosniff');
      headers.set('content-security-policy',"default-src 'none'; sandbox");
      return new Response(image.body,{headers});
    }
    // Admin routes use a secret in the header, never a URL or the app.
    if (url.pathname.startsWith('/fan/admin/')) {
      const secret = env.ADMIN_TOKEN || env.STATS_TOKEN;
      if (!secret || request.headers.get('authorization') !== `Bearer ${secret}`) return fail('Unauthorized', 401);
      if (url.pathname === '/fan/admin/matches' && request.method === 'GET') {
        const rows = await db.prepare('SELECT match_key,title,kickoff,COUNT(*) AS picks FROM fan_picks GROUP BY match_key ORDER BY kickoff DESC LIMIT 300').all();
        return json({matches:rows.results});
      }
      if (url.pathname === '/fan/admin/reports' && request.method === 'GET') {
        const rows = await db.prepare(`SELECT r.message_id,r.reason,m.text,m.room,u.name,COUNT(*) AS reports FROM fan_reports r JOIN fan_messages m ON m.id=r.message_id JOIN fan_users u ON u.id=m.user_id WHERE m.hidden=0 GROUP BY r.message_id ORDER BY reports DESC LIMIT 100`).all();
        const posts = await db.prepare(`SELECT r.post_id,p.text,p.kind,p.image_key,u.name,COUNT(*) AS reports FROM fan_post_reports r JOIN fan_posts p ON p.id=r.post_id JOIN fan_users u ON u.id=p.user_id WHERE p.hidden=0 GROUP BY r.post_id ORDER BY reports DESC LIMIT 100`).all();
        return json({reports:rows.results,post_reports:posts.results});
      }
      if (request.method !== 'POST') return fail('Method not allowed',405);
      const b = await request.json();
      if (url.pathname === '/fan/admin/hide-post') {
        if(typeof b.id!=='string' || b.id.length>100)return fail('Invalid post');
        const post=await db.prepare('SELECT image_key FROM fan_posts WHERE id=?').bind(b.id).first();
        if(!post)return fail('Post not found',404);
        await db.prepare('UPDATE fan_posts SET hidden=1 WHERE id=?').bind(b.id).run();
        if(post.image_key && env.FAN_MEDIA)await env.FAN_MEDIA.delete(post.image_key).catch(e=>console.error('Image cleanup failed',e));
        return json({ok:true});
      }
      if (url.pathname === '/fan/admin/hide') {
        if (typeof b.id !== 'string' || b.id.length > 100) return fail('Invalid message');
        await db.prepare('UPDATE fan_messages SET hidden=1 WHERE id=?').bind(b.id).run();
        return json({ok:true});
      }
      if (url.pathname === '/fan/admin/result') {
        if (!Number.isInteger(b.home) || !Number.isInteger(b.away) || b.home<0 || b.away<0 || b.home>50 || b.away>50) return fail('Invalid final score');
        const pick = await db.prepare('SELECT kickoff FROM fan_picks WHERE match_key=? LIMIT 1').bind(String(b.key)).first();
        if (!pick || pick.kickoff > Date.now()) return fail('No started prediction match for this key');
        await db.prepare('INSERT INTO fan_results(match_key,home,away) VALUES(?,?,?) ON CONFLICT(match_key) DO UPDATE SET home=excluded.home,away=excluded.away').bind(b.key,b.home,b.away).run();
        return json({ok:true});
      }
      return fail('Not found',404);
    }
    const token = (request.headers.get('authorization') || '').replace(/^Bearer /, '');
    let id;
    if(env.GOOGLE_WEB_CLIENT_ID) {
      const identity=await verifyFanGoogleToken(token,env);
      if(!identity)return fail('Please log in to Deeprowss again.',401);
      id=await fanHash('google:'+identity.sub);
      if(!await db.prepare('SELECT id FROM fan_accounts WHERE id=?').bind(id).first())return fail('Please register your Deeprowss account first.',403);
    } else {
      // Legacy compatibility until the Google client ID is configured.
      if (!/^[a-f0-9]{64}$/.test(token)) return fail('Invalid fan identity',401);
      id = await fanHash(token);
    }
    const user = await db.prepare('SELECT * FROM fan_users WHERE id=?').bind(id).first();
    if(url.pathname==='/fan/posts' || url.pathname==='/fan/post' || url.pathname.startsWith('/fan/post/')) {
      return await fanPosts(request,env,url,user,id);
    }
    if (request.method === 'GET' && url.pathname === '/fan/state') {
      const picks = await db.prepare(`SELECT p.*,r.home AS result_home,r.away AS result_away FROM fan_picks p LEFT JOIN fan_results r ON r.match_key=p.match_key WHERE p.user_id=? ORDER BY p.kickoff DESC LIMIT 300`).bind(id).all();
      const week = fanWeek();
      const board = await db.prepare(`SELECT u.id,u.name, SUM(CASE WHEN p.home=r.home AND p.away=r.away THEN 3 WHEN (p.home>p.away AND r.home>r.away) OR (p.home<p.away AND r.home<r.away) OR (p.home=p.away AND r.home=r.away) THEN 1 ELSE 0 END) AS points,COUNT(*) AS played FROM fan_picks p JOIN fan_results r ON r.match_key=p.match_key JOIN fan_users u ON u.id=p.user_id WHERE p.kickoff>=? AND p.kickoff<? GROUP BY u.id ORDER BY points DESC,played ASC,u.id ASC LIMIT 100`).bind(week,week+604800000).all();
      return json({id,name:user?.name || '',week,leaderboard:board.results,picks:picks.results});
    }
    if (request.method === 'GET' && url.pathname === '/fan/messages') {
      const room = url.searchParams.get('room') || '';
      if (!room || room.length>200) return fail('Invalid room');
      const messages = await db.prepare(`SELECT m.id,m.user_id,u.name,m.text,m.at FROM fan_messages m JOIN fan_users u ON u.id=m.user_id WHERE m.room=? AND m.hidden=0 ORDER BY m.at DESC LIMIT 80`).bind(room).all();
      return json({messages:messages.results.reverse()});
    }
    if (request.method !== 'POST') return fail('Not found',404);
    const bodyText = await request.text();
    if (bodyText.length>4096) return fail('Request too large',413);
    const b = JSON.parse(bodyText);
    if (url.pathname === '/fan/profile') {
      const name = typeof b.name==='string' ? b.name.trim() : '';
      if (name.length<3 || name.length>30 || /[\u0000-\u001f<>]/.test(name)) return fail('Choose a name of 3–30 characters');
      if (!user) {
        const ip = request.headers.get('CF-Connecting-IP') || 'local';
        const bucket = `${await fanHash(ip)}:${Math.floor(Date.now()/3600000)}`;
        const count = await db.prepare(`INSERT INTO fan_limits(bucket,count) VALUES(?,1) ON CONFLICT(bucket) DO UPDATE SET count=count+1 RETURNING count`).bind(bucket).first();
        if (count.count>10) return fail('Too many new profiles. Try later.',429);
        await db.prepare('DELETE FROM fan_limits WHERE bucket NOT LIKE ?').bind(`%:${Math.floor(Date.now()/3600000)}`).run();
      }
      await db.prepare('INSERT INTO fan_users(id,name) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name').bind(id,name).run();
      return json({ok:true});
    }
    if (!user) return fail('Choose your Fan Zone nickname first.',403);
    if (url.pathname === '/fan/pick') {
      if (!Number.isInteger(b.home) || !Number.isInteger(b.away) || b.home<0 || b.away<0 || b.home>20 || b.away>20) return fail('Scores must be between 0 and 20');
      const fixtures = await fanFixtures(env);
      const f = fixtures.find(f => fanKey(f)===b.key);
      if (!f) return fail('Match is no longer available. Refresh the fixtures.');
      const kickoff = new Date(f.kickoff).getTime();
      if (Date.now()>=kickoff) return fail('Predictions are locked at kickoff.',409);
      // The final cutoff check runs in the same statement as the write.
      const saved = await db.prepare(`INSERT INTO fan_picks(user_id,match_key,title,kickoff,home,away) SELECT ?,?,?,?,?,? WHERE (unixepoch('now')*1000)<? ON CONFLICT(user_id,match_key) DO UPDATE SET home=excluded.home,away=excluded.away WHERE (unixepoch('now')*1000)<fan_picks.kickoff`).bind(id,b.key,`${f.home} vs ${f.away}`,kickoff,b.home,b.away,kickoff).run();
      if ((saved.meta?.changes ?? saved.changes ?? 0) === 0) return fail('Predictions are locked at kickoff.',409);
      return json({ok:true});
    }
    if (url.pathname === '/fan/message') {
      const text = typeof b.text==='string' ? b.text.trim() : '';
      if (!text || text.length>300) return fail('Write 1–300 characters');
      if (typeof b.room!=='string' || b.room.length>200) return fail('Invalid room');
      if (b.room!=='lounge') {
        const fixtures = await fanFixtures(env);
        if (!fixtures.some(f=>fanKey(f)===b.room)) return fail('This match discussion is closed.');
      }
      const now = Date.now();
      const limit = await db.prepare('UPDATE fan_users SET last_post=? WHERE id=? AND last_post<? RETURNING id').bind(now,id,now-10000).first();
      if (!limit) return fail('Please wait 10 seconds between posts.',429);
      await db.prepare('INSERT INTO fan_messages(id,room,user_id,text,at) VALUES(?,?,?,?,?)').bind(crypto.randomUUID(),b.room,id,text,now).run();
      return json({ok:true});
    }
    if (url.pathname === '/fan/report') {
      const message = await db.prepare('SELECT id FROM fan_messages WHERE id=?').bind(String(b.id)).first();
      if (!message) return fail('Message not found',404);
      await db.prepare('INSERT OR IGNORE INTO fan_reports(message_id,user_id,reason) VALUES(?,?,?)').bind(b.id,id,String(b.reason || 'Inappropriate content').slice(0,200)).run();
      return json({ok:true});
    }
    return fail('Not found',404);
  } catch (e) {
    console.error('Fan Zone request failed', e);
    return fail('Fan Zone is unavailable. Check the Worker setup and try again.',503);
  }
}

const FAN_IMAGE_LIMIT = 4 * 1024 * 1024;
export function fanImageType(bytes) {
  let width = 0, height = 0, type = '';
  if (bytes.length >= 33 && [137,80,78,71,13,10,26,10].every((b,i)=>bytes[i]===b) &&
      String.fromCharCode(...bytes.slice(12,16))==='IHDR') {
    const view = new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
    width=view.getUint32(16);height=view.getUint32(20);type='image/png';
  } else if (bytes.length>=4 && bytes[0]===255 && bytes[1]===216) {
    let pos=2;
    while(pos+3<bytes.length) {
      if(bytes[pos++]!==255) break;
      while(bytes[pos]===255) pos++;
      const marker=bytes[pos++];
      if(marker===217 || marker===218) break;
      if(marker===1 || (marker>=208 && marker<=215)) continue;
      if(pos+1>=bytes.length) break;
      const length=bytes[pos]*256+bytes[pos+1];
      if(length<2 || pos+length>bytes.length) break;
      if([192,193,194,195,197,198,199,201,202,203,205,206,207].includes(marker) && length>=8) {
        height=bytes[pos+3]*256+bytes[pos+4];width=bytes[pos+5]*256+bytes[pos+6];type='image/jpeg';break;
      }
      pos+=length;
    }
  }
  return type && width>0 && height>0 && width<=6000 && height<=6000 && width*height<=16000000 ? type : null;
}
async function fanReadForm(request) {
  const max=FAN_IMAGE_LIMIT+65536;
  if(Number(request.headers.get('content-length') || 0)>max) return null;
  if(!request.body) return null;
  const reader=request.body.getReader(), chunks=[];
  let size=0;
  while(true) {
    const {done,value}=await reader.read();
    if(done)break;
    size+=value.byteLength;
    if(size>max){await reader.cancel();return null;}
    chunks.push(value);
  }
  const bytes=new Uint8Array(size);let offset=0;
  for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  try {
    return await new Response(bytes,{headers:{'content-type':request.headers.get('content-type') || ''}}).formData();
  } catch (_) {return null;}
}
async function fanPosts(request,env,url,user,id) {
  const db=env.DB;
  const fail=(error,status=400)=>json({error},status);
  if(request.method==='GET' && url.pathname==='/fan/posts') {
    const kind=url.searchParams.get('kind') || 'all';
    if(!['all','prediction','betslip','banter'].includes(kind)) return fail('Invalid post filter');
    const before=url.searchParams.get('before') || '';
    const cursor=before ? /^(\d+):([a-f0-9-]{36})$/.exec(before) : null;
    if(before && !cursor)return fail('Invalid page cursor');
    const rows=await db.prepare(`SELECT p.id,p.user_id,u.name,p.kind,p.text,p.at,CASE WHEN p.image_key<>'' THEN 1 ELSE 0 END AS has_image FROM fan_posts p JOIN fan_users u ON u.id=p.user_id WHERE p.hidden=0 AND (?='all' OR p.kind=?) AND (p.at<? OR (p.at=? AND p.id<?)) ORDER BY p.at DESC,p.id DESC LIMIT 41`)
      .bind(kind,kind,cursor?Number(cursor[1]):Number.MAX_SAFE_INTEGER,cursor?Number(cursor[1]):Number.MAX_SAFE_INTEGER,cursor?cursor[2]:'~').all();
    const posts=rows.results.slice(0,40);
    const last=posts.at(-1);
    return json({posts,next:rows.results.length>40?`${last.at}:${last.id}`:null,id,uploads_enabled:Boolean(env.FAN_MEDIA)});
  }
  if(!user) return fail('Choose your Fan Zone nickname first.',403);
  if(request.method==='POST' && url.pathname==='/fan/post') {
    if(!(request.headers.get('content-type') || '').startsWith('multipart/form-data'))return fail('Use a photo/text form');
    const form=await fanReadForm(request);
    if(!form)return fail('Invalid upload or image exceeds 4 MB.',413);
    const kind=String(form.get('kind') || 'banter');
    const text=String(form.get('text') || '').trim();
    if(!['prediction','betslip','banter'].includes(kind) || text.length>1000)return fail('Choose a post type and keep text within 1,000 characters');
    const file=form.get('image');
    const hasImage=file && typeof file!=='string' && file.size>0;
    if(!text && !hasImage)return fail('Write something or attach a photo');
    if(kind==='prediction' && !text)return fail('Write your prediction before posting');
    if(kind==='betslip' && !hasImage)return fail('Attach your bet-slip image');
    let bytes,type;
    if(hasImage) {
      if(!env.FAN_MEDIA)return fail('Image uploads need the FAN_MEDIA R2 binding. Text posts still work.',503);
      if(file.size>FAN_IMAGE_LIMIT)return fail('Choose an image smaller than 4 MB.',413);
      bytes=new Uint8Array(await file.arrayBuffer());
      type=fanImageType(bytes);
      if(!type)return fail('Choose a JPG or PNG image, up to 6,000 pixels per side and 16 megapixels.');
    }
    const now=Date.now();
    // A shared per-profile cooldown also applies across lounge and feed posts.
    const allowed=await db.prepare('UPDATE fan_users SET last_post=? WHERE id=? AND last_post<? RETURNING id').bind(now,id,now-10000).first();
    if(!allowed)return fail('Please wait 10 seconds between posts.',429);
    const postId=crypto.randomUUID();
    const imageKey=hasImage?`fan-posts/${postId}`:'';
    try {
      if(hasImage)await env.FAN_MEDIA.put(imageKey,bytes,{httpMetadata:{contentType:type}});
      await db.prepare('INSERT INTO fan_posts(id,user_id,kind,text,image_key,at) VALUES(?,?,?,?,?,?)').bind(postId,id,kind,text,imageKey,now).run();
    } catch(e) {
      if(imageKey)await env.FAN_MEDIA.delete(imageKey).catch(()=>{});
      throw e;
    }
    return json({ok:true,id:postId});
  }
  if(request.method==='POST' && ['/fan/post/report','/fan/post/delete'].includes(url.pathname)) {
    const raw=await request.text();
    if(raw.length>4096)return fail('Request too large',413);
    let b;try{b=JSON.parse(raw);}catch(_){return fail('Invalid request');}
    if(typeof b.id!=='string' || b.id.length>100)return fail('Invalid post');
    const post=await db.prepare('SELECT user_id,image_key FROM fan_posts WHERE id=? AND hidden=0').bind(b.id).first();
    if(!post)return fail('Post not found',404);
    if(url.pathname==='/fan/post/delete') {
      if(post.user_id!==id)return fail('You can only delete your own posts.',403);
      await db.prepare('UPDATE fan_posts SET hidden=1 WHERE id=?').bind(b.id).run();
      // Access is denied immediately by the DB flag, even if object cleanup fails.
      if(post.image_key && env.FAN_MEDIA)await env.FAN_MEDIA.delete(post.image_key).catch(e=>console.error('Image cleanup failed',e));
    } else {
      await db.prepare('INSERT OR IGNORE INTO fan_post_reports(post_id,user_id,reason) VALUES(?,?,?)').bind(b.id,id,String(b.reason || 'Inappropriate content').slice(0,200)).run();
    }
    return json({ok:true});
  }
  return fail('Not found',404);
}

// Google authentication for Deeprowss. Tokens are verified with Google's
// rotating public keys; private client secrets are never embedded in the APK.
let googleKeys = [], googleKeysUntil = 0, googleKeysFetched = 0;
function googleDecode(part) {
  const padded = part.replace(/-/g,'+').replace(/_/g,'/');
  return Uint8Array.from(atob(padded.padEnd(Math.ceil(padded.length/4)*4,'=')),c=>c.charCodeAt(0));
}
export async function verifyFanGoogleToken(token, env) {
  if(typeof token!=='string' || token.length>8192 || !env.GOOGLE_WEB_CLIENT_ID)return null;
  let header,claims,signature,parts;
  try {
    parts=token.split('.');if(parts.length!==3)return null;
    header=JSON.parse(new TextDecoder().decode(googleDecode(parts[0])));
    claims=JSON.parse(new TextDecoder().decode(googleDecode(parts[1])));
    signature=googleDecode(parts[2]);
  } catch (_) {return null;}
  const now=Math.floor(Date.now()/1000);
  if(header.alg!=='RS256' || typeof header.kid!=='string' || header.kid.length>200 ||
    !['accounts.google.com','https://accounts.google.com'].includes(claims.iss) ||
    claims.aud!==env.GOOGLE_WEB_CLIENT_ID || !Number.isFinite(claims.exp) || claims.exp<=now ||
    !Number.isFinite(claims.iat) || claims.iat>now+60 || claims.iat>=claims.exp ||
    typeof claims.sub!=='string' || !claims.sub || claims.sub.length>255 ||
    (claims.email_verified!==true && claims.email_verified!=='true') ||
    typeof claims.email!=='string' || !/@(gmail|googlemail)\.com$/i.test(claims.email))return null;
  if(Date.now()>=googleKeysUntil || (!googleKeys.some(k=>k.kid===header.kid) && Date.now()-googleKeysFetched>60000)) {
    const response=await fetch('https://www.googleapis.com/oauth2/v3/certs',{signal:AbortSignal.timeout(10000)});
    if(!response.ok)throw new Error('Google verification keys unavailable');
    const data=await response.json();
    if(!Array.isArray(data.keys))throw new Error('Google verification keys unavailable');
    googleKeys=data.keys;googleKeysFetched=Date.now();
    const maxAge=Number(/max-age=(\d+)/.exec(response.headers.get('cache-control') || '')?.[1] || 3600);
    googleKeysUntil=Date.now()+Math.min(maxAge,86400)*1000;
  }
  const jwk=googleKeys.find(k=>k.kid===header.kid && k.kty==='RSA');
  if(!jwk)return null;
  try {
    const key=await crypto.subtle.importKey('jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
    if(!await crypto.subtle.verify('RSASSA-PKCS1-v1_5',key,signature,new TextEncoder().encode(parts[0]+'.'+parts[1])))return null;
  } catch (_) {return null;}
  return {sub:claims.sub,email:claims.email.toLowerCase(),name:String(claims.name || 'Football Fan').slice(0,100),
    photo:typeof claims.picture==='string' && claims.picture.startsWith('https://')?claims.picture:''};
}
async function fanMigrateInstall(db,legacyToken,id,isNew) {
  if(typeof legacyToken!=='string' || !/^[a-f0-9]{64}$/.test(legacyToken))return;
  const legacy=await fanHash(legacyToken);
  if(legacy===id)return;
  const guard='EXISTS(SELECT 1 FROM fan_legacy_claims WHERE legacy_id=? AND account_id=?)';
  await db.batch([
    db.prepare('INSERT OR IGNORE INTO fan_legacy_claims(legacy_id,account_id) SELECT ?,? WHERE EXISTS(SELECT 1 FROM fan_users WHERE id=?)').bind(legacy,id,legacy),
    db.prepare(`UPDATE fan_users SET name=(SELECT name FROM fan_users WHERE id=?) WHERE id=? AND ?=1 AND ${guard}`).bind(legacy,id,isNew?1:0,legacy,id),
    db.prepare(`INSERT OR IGNORE INTO fan_picks(user_id,match_key,title,kickoff,home,away) SELECT ?,match_key,title,kickoff,home,away FROM fan_picks WHERE user_id=? AND ${guard}`).bind(id,legacy,legacy,id),
    db.prepare(`DELETE FROM fan_picks WHERE user_id=? AND ${guard}`).bind(legacy,legacy,id),
    db.prepare(`UPDATE fan_messages SET user_id=? WHERE user_id=? AND ${guard}`).bind(id,legacy,legacy,id),
    db.prepare(`UPDATE fan_posts SET user_id=? WHERE user_id=? AND ${guard}`).bind(id,legacy,legacy,id),
    db.prepare(`UPDATE OR IGNORE fan_reports SET user_id=? WHERE user_id=? AND ${guard}`).bind(id,legacy,legacy,id),
    db.prepare(`DELETE FROM fan_reports WHERE user_id=? AND ${guard}`).bind(legacy,legacy,id),
    db.prepare(`UPDATE OR IGNORE fan_post_reports SET user_id=? WHERE user_id=? AND ${guard}`).bind(id,legacy,legacy,id),
    db.prepare(`DELETE FROM fan_post_reports WHERE user_id=? AND ${guard}`).bind(legacy,legacy,id),
    db.prepare(`DELETE FROM fan_users WHERE id=? AND ${guard}`).bind(legacy,legacy,id),
  ]);
}
async function fanAccountAuth(request,env) {
  const fail=(error,status=400,switchTo)=>json({error,...(switchTo?{switchTo}:{})},status);
  if(request.method!=='POST')return fail('Method not allowed',405);
  if(!env.GOOGLE_WEB_CLIENT_ID)return fail('Set GOOGLE_WEB_CLIENT_ID on this Worker before enabling Google sign-in.',503);
  const raw=await request.text();if(raw.length>12000)return fail('Request too large',413);
  let body;try{body=JSON.parse(raw);}catch(_){return fail('Invalid request');}
  if(!['signup','login'].includes(body.mode))return fail('Choose sign up or log in');
  const identity=await verifyFanGoogleToken(body.idToken,env);
  if(!identity)return fail('Could not verify this Gmail account. Please sign in again.',401);
  const id=await fanHash('google:'+identity.sub), db=env.DB;
  let account=await db.prepare('SELECT id FROM fan_accounts WHERE id=?').bind(id).first();
  const isNew=body.mode==='signup';
  if(isNew && account)return fail('This Gmail already has a Deeprowss account. Please log in.',409,'login');
  if(!isNew && !account)return fail('This Gmail has not registered for Deeprowss yet. Please sign up.',404,'signup');
  if(isNew) {
    const results=await db.batch([
      db.prepare('INSERT OR IGNORE INTO fan_accounts(id,google_sub,email,name,photo,created_at) VALUES(?,?,?,?,?,?)').bind(id,identity.sub,identity.email,identity.name,identity.photo,Date.now()),
      db.prepare('INSERT OR IGNORE INTO fan_users(id,name) VALUES(?,?)').bind(id,identity.name.slice(0,30)),
    ]);
    if((results[0].meta?.changes ?? results[0].changes ?? 0)!==1)return fail('This Gmail already has an account. Please log in.',409,'login');
  } else {
    await db.prepare('UPDATE fan_accounts SET email=?,name=?,photo=? WHERE id=?').bind(identity.email,identity.name,identity.photo,id).run();
  }
  await fanMigrateInstall(db,body.legacyToken,id,isNew);
  return json({ok:true,user:{id,email:identity.email,name:identity.name,photo:identity.photo}});
}
