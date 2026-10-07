// Run: node cloudflare/worker.test.mjs   (Node 20+)
import assert from "node:assert/strict";

// --- tiny Cloudflare runtime stand-ins
const store = new Map();
globalThis.caches = { default: {
  match: async (req) => { const r = store.get(req.url); return r ? r.clone() : undefined; },
  put: async (req, res) => { store.set(req.url, res); },
} };
let upstreamCalls = 0;
let upstreamStatus = 200;
const realFetch = globalThis.fetch;
globalThis.fetch = async (url, opts) => {
  const u = String(url);
  if (u.includes("api.cloudflare.com")) {
    const sql = opts.body;
    assert.match(opts.headers.authorization, /^Bearer tok/);
    const data = /COUNT\(DISTINCT blob4\) AS phones FROM deeprowss_app WHERE timestamp > NOW\(\) - INTERVAL '1' DAY FORMAT/.test(sql)
      ? [{ requests: 1234, phones: 56 }] : [{ day: "2026-10-07 00:00:00", country: "NG", version: "1.0.9", file: "movies.json", requests: 10, phones: 3 }];
    return new Response(JSON.stringify({ data }), { status: 200 });
  }
  upstreamCalls++;
  if (upstreamStatus !== 200) return new Response("nope", { status: upstreamStatus });
  return new Response(JSON.stringify([{ name: "x", url: "u" }]), { status: 200 });
};

const worker = (await import("./worker.js")).default;
const points = [];
const env = { ANALYTICS: { writeDataPoint: (p) => points.push(p) }, STATS_TOKEN: "secret", CF_ACCOUNT_ID: "acc", CF_API_TOKEN: "tok123" };
const ctx = { waitUntil: (p) => p };
const get = (path, headers = {}) =>
  worker.fetch(Object.assign(new Request("https://feed.example.com" + path, { headers }), { cf: { country: "NG" } }), env, ctx);

// 1. feed: miss then hit, query string ignored for caching, CORS, analytics recorded
let r = await get("/feed/movies.json?_refresh=111", { "x-install-id": "abc123", "x-app-version": "1.0.9", "x-platform": "android" });
assert.equal(r.status, 200); assert.equal(r.headers.get("x-feed-cache"), "MISS");
assert.equal((await r.json())[0].name, "x");
await new Promise((x) => setTimeout(x, 5));
r = await get("/feed/movies.json?_refresh=222");
assert.equal(r.headers.get("x-feed-cache"), "HIT"); assert.equal(upstreamCalls, 1);
assert.equal(r.headers.get("access-control-allow-origin"), "*");
assert.equal(points.length, 2);
assert.deepEqual(points[0].blobs, ["movies.json", "1.0.9", "android", "abc123", "NG", "MISS"]);
assert.equal(points[1].blobs[3], "unknown");

// 2. unknown file / path
assert.equal((await get("/feed/secret.json")).status, 404);
assert.equal((await get("/nothing")).status, 404);
assert.equal((await get("/health")).status, 200);

// 3. origin failure -> 502 and not cached
store.clear(); upstreamStatus = 500;
r = await get("/feed/tv.json"); assert.equal(r.status, 502);
upstreamStatus = 200; r = await get("/feed/tv.json"); assert.equal(r.status, 200);

// 4. works without the analytics binding
const bare = { }; r = await worker.fetch(Object.assign(new Request("https://f.example.com/feed/ticker.json"), { cf: {} }), bare, ctx);
assert.equal(r.status, 200);

// 5. stats: needs token; renders numbers
assert.equal((await get("/stats")).status, 404);
assert.equal((await get("/stats?token=wrong")).status, 404);
r = await get("/stats?token=secret"); const page = await r.text();
assert.equal(r.status, 200); assert.match(page, /1,234/); assert.match(page, /phones \(24 h\)/);
console.log("worker.js: all tests passed");
globalThis.fetch = realFetch;
