/**
 * Deeprowss feed proxy + anonymous usage monitor (Cloudflare Worker).
 *
 *   App  ->  https://feed.<your-domain>/feed/movies.json  ->  this Worker
 *                                                              |-> GitHub raw (cached ~30 s at Cloudflare's edge)
 *                                                              '-> Analytics Engine (who / where / which version)
 *
 * What you can see afterwards
 *   * Cloudflare dashboard: Workers > this Worker > Metrics (requests, errors,
 *     CPU) and your domain > Analytics > Traffic (requests, countries, status).
 *   * https://feed.<your-domain>/stats?token=<STATS_TOKEN>  (optional page
 *     built into this Worker): requests and DISTINCT PHONES per day, top
 *     countries, app versions and files.
 *
 * Settings (Worker > Settings > Variables and Secrets)
 *   GITHUB_RAW_BASE  optional  default: raw.githubusercontent.com/.../assets/data
 *   FEED_TTL         optional  seconds to cache a file at the edge (default 30)
 *   STATS_TOKEN      secret    enables /stats (any long random text)
 *   CF_ACCOUNT_ID    secret    your Cloudflare account id        (for /stats)
 *   CF_API_TOKEN     secret    API token with "Account Analytics: Read" (for /stats)
 *   ANALYTICS        binding   Analytics Engine, dataset "deeprowss_app"
 *
 * Only an anonymous random install id, app version, platform and the country
 * Cloudflare derives from the connection are recorded. No names, no emails.
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
  "access-control-allow-headers": "x-install-id, x-app-version, x-platform",
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (request.method !== "GET" && request.method !== "HEAD") {
      return json({ error: "method not allowed" }, 405);
    }

    if (url.pathname === "/" || url.pathname === "/health") {
      return json({ ok: true, service: "deeprowss-feed" });
    }

    if (url.pathname === "/stats") return stats(url, env);

    const m = /^\/feed\/([a-z0-9_-]+\.json)$/i.exec(url.pathname);
    if (m && FILES[m[1].toLowerCase()]) {
      return feed(request, env, ctx, m[1].toLowerCase());
    }

    return json({ error: "not found" }, 404);
  },
};

// ------------------------------------------------------------------ feed

async function feed(request, env, ctx, file) {
  const ttl = clamp(parseInt(env.FEED_TTL ?? "30", 10) || 30, 0, 600);
  const base = (env.GITHUB_RAW_BASE || DEFAULT_RAW_BASE).replace(/\/+$/, "");
  const origin = `${base}/${FILES[file]}`;

  // The app adds ?_refresh=<time> to every request; ignore it for caching,
  // otherwise nothing could ever be served from the edge cache.
  const cacheKey = new Request(`https://feed-cache.invalid/${file}`);
  const cache = caches.default;

  let status = 200;
  let cacheState = "HIT";
  let response = ttl > 0 ? await cache.match(cacheKey) : undefined;

  if (!response) {
    cacheState = "MISS";
    try {
      const upstream = await fetch(origin, {
        headers: { "user-agent": "deeprowss-feed-worker", accept: "application/json" },
        cf: { cacheTtl: 0, cacheEverything: false },
      });
      if (!upstream.ok) {
        status = 502;
        response = json({ error: "origin returned " + upstream.status }, 502);
      } else {
        const body = await upstream.text();
        response = new Response(body, {
          status: 200,
          headers: {
            "content-type": "application/json; charset=utf-8",
            "cache-control": `public, max-age=${ttl}`,
          },
        });
        if (ttl > 0) ctx.waitUntil(cache.put(cacheKey, response.clone()));
      }
    } catch (e) {
      status = 502;
      response = json({ error: "origin unreachable" }, 502);
    }
  }

  record(env, request, file, status, cacheState);

  const out = new Response(response.body, response);
  for (const [k, v] of Object.entries(CORS)) out.headers.set(k, v);
  out.headers.set("cache-control", "no-cache"); // the Worker (not the phone) caches
  out.headers.set("x-feed-cache", cacheState);
  return out;
}

function record(env, request, file, status, cacheState) {
  try {
    if (!env.ANALYTICS) return;
    const h = request.headers;
    env.ANALYTICS.writeDataPoint({
      indexes: [file],
      blobs: [
        file,                                                   // blob1 file
        (h.get("x-app-version") || "unknown").slice(0, 32),     // blob2 app version
        (h.get("x-platform") || "unknown").slice(0, 16),        // blob3 platform
        (h.get("x-install-id") || "unknown").slice(0, 64),      // blob4 anonymous phone id
        request.cf?.country || "??",                            // blob5 country
        cacheState,                                             // blob6 edge cache
      ],
      doubles: [1, status],
    });
  } catch (_) {
    /* analytics must never break the feed */
  }
}

// ----------------------------------------------------------------- stats

async function stats(url, env) {
  if (!env.STATS_TOKEN || url.searchParams.get("token") !== env.STATS_TOKEN) {
    return new Response("Not found", { status: 404 });
  }
  if (!env.CF_ACCOUNT_ID || !env.CF_API_TOKEN) {
    return html(page("Stats not configured",
      "<p>Add the secrets <b>CF_ACCOUNT_ID</b> and <b>CF_API_TOKEN</b> (token with <i>Account Analytics: Read</i>) to this Worker.</p>"));
  }

  const t = DATASET;
  const q = {
    today:
      `SELECT SUM(_sample_interval) AS requests, COUNT(DISTINCT blob4) AS phones FROM ${t} WHERE timestamp > NOW() - INTERVAL '1' DAY`,
    days:
      `SELECT toStartOfInterval(timestamp, INTERVAL '1' DAY) AS day, SUM(_sample_interval) AS requests, COUNT(DISTINCT blob4) AS phones FROM ${t} WHERE timestamp > NOW() - INTERVAL '7' DAY GROUP BY day ORDER BY day DESC`,
    countries:
      `SELECT blob5 AS country, SUM(_sample_interval) AS requests, COUNT(DISTINCT blob4) AS phones FROM ${t} WHERE timestamp > NOW() - INTERVAL '7' DAY GROUP BY country ORDER BY phones DESC LIMIT 15`,
    versions:
      `SELECT blob2 AS version, COUNT(DISTINCT blob4) AS phones FROM ${t} WHERE timestamp > NOW() - INTERVAL '7' DAY GROUP BY version ORDER BY phones DESC LIMIT 10`,
    files:
      `SELECT blob1 AS file, SUM(_sample_interval) AS requests FROM ${t} WHERE timestamp > NOW() - INTERVAL '1' DAY GROUP BY file ORDER BY requests DESC`,
  };

  try {
    const res = {};
    for (const [k, sql] of Object.entries(q)) res[k] = await runSql(env, sql);

    const today = res.today[0] || {};
    const body = `
      <div class="grid">
        <div class="big"><span>${num(today.phones)}</span>phones (24 h)</div>
        <div class="big"><span>${num(today.requests)}</span>requests (24 h)</div>
      </div>
      ${table("Last 7 days", ["day", "phones", "requests"],
        res.days.map((r) => [String(r.day).slice(0, 10), num(r.phones), num(r.requests)]))}
      ${table("Countries (7 days)", ["country", "phones", "requests"],
        res.countries.map((r) => [r.country, num(r.phones), num(r.requests)]))}
      ${table("App versions (7 days)", ["version", "phones"],
        res.versions.map((r) => [r.version, num(r.phones)]))}
      ${table("Files (24 h)", ["file", "requests"],
        res.files.map((r) => [r.file, num(r.requests)]))}
      <p class="muted">"Phones" = distinct anonymous install ids. Data appears a minute or two after use.</p>`;
    return html(page("Deeprowss usage", body));
  } catch (e) {
    return html(page("Stats error", `<p>${esc(String(e.message || e))}</p>`), 500);
  }
}

async function runSql(env, sql) {
  const r = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${env.CF_ACCOUNT_ID}/analytics_engine/sql`,
    {
      method: "POST",
      headers: { authorization: `Bearer ${env.CF_API_TOKEN}` },
      body: sql + " FORMAT JSON",
    },
  );
  const text = await r.text();
  if (!r.ok) throw new Error(`Analytics query failed (${r.status}): ${text.slice(0, 300)}`);
  return JSON.parse(text).data || [];
}

// --------------------------------------------------------------- helpers

const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));
const num = (v) => Number(v || 0).toLocaleString("en-US");
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...CORS },
  });
}

function html(body, status = 200) {
  return new Response(body, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-robots-tag": "noindex" },
  });
}

function table(title, head, rows) {
  if (!rows.length) return `<h2>${esc(title)}</h2><p class="muted">No data yet.</p>`;
  return `<h2>${esc(title)}</h2><table><tr>${head.map((h) => `<th>${esc(h)}</th>`).join("")}</tr>${
    rows.map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join("")}</tr>`).join("")}</table>`;
}

function page(title, body) {
  return `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title>
<style>
body{margin:0;padding:18px;background:#0b0f17;color:#e8ecf3;font:15px/1.45 system-ui,sans-serif}
h1{font-size:20px;margin:0 0 14px}h2{font-size:15px;margin:22px 0 8px;color:#9fb0c8}
.grid{display:flex;gap:10px}.big{flex:1;background:#131a26;border:1px solid #243047;border-radius:14px;padding:14px;color:#9fb0c8;font-size:12.5px}
.big span{display:block;font-size:28px;font-weight:800;color:#fff}
table{width:100%;border-collapse:collapse;background:#131a26;border-radius:12px;overflow:hidden}
th,td{padding:8px 10px;text-align:left;border-bottom:1px solid #1d2739}th{color:#9fb0c8;font-weight:600;font-size:12.5px}
.muted{color:#7d8ca3;font-size:12.5px}
</style></head><body><h1>${esc(title)}</h1>${body}</body></html>`;
}
