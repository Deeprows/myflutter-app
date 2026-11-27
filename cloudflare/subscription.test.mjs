// Run: node --no-warnings cloudflare/subscription.test.mjs   (Node 22+)
// Uses Node's built-in SQLite as a stand-in for Cloudflare D1.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { createHmac } from "node:crypto";

const store = new Map();
globalThis.caches = { default: {
  match: async (req) => { const r = store.get(req.url); return r ? r.clone() : undefined; },
  put: async (req, res) => { store.set(req.url, res); },
} };

// ---- fake Paystack + exchange-rate API
const txs = new Map();           // reference -> transaction object
let initBody = null;
const telegramMessages = [];
const pendingNotifications = [];
globalThis.fetch = async (url, opts = {}) => {
  const u = String(url);
  if (u.includes("api.telegram.org/bot")) {
    telegramMessages.push(JSON.parse(opts.body));
    return new Response(JSON.stringify({ ok: true, result: { message_id: telegramMessages.length } }));
  }
  if (u.includes("open.er-api.com")) {
    return new Response(JSON.stringify({ rates: { USD: 0.00065, GHS: 0.0099 } }));
  }
  if (u.endsWith("/transaction/initialize")) {
    assert.equal(opts.headers.authorization, "Bearer sk_test");
    initBody = JSON.parse(opts.body);
    txs.set(initBody.reference, {
      status: "success", reference: initBody.reference, currency: "NGN",
      amount: initBody.plan ? 200000 : initBody.amount,
      customer: { email: initBody.email }, metadata: initBody.metadata,
    });
    return new Response(JSON.stringify({ status: true, data: { authorization_url: "https://checkout.paystack.com/x", reference: initBody.reference } }));
  }
  const m = /\/transaction\/verify\/(.+)$/.exec(u);
  if (m) {
    const t = txs.get(decodeURIComponent(m[1]));
    return new Response(JSON.stringify(t ? { status: true, data: t } : { status: false, message: "not found" }), { status: t ? 200 : 404 });
  }
  throw new Error("unexpected fetch " + u);
};

// ---- D1 stand-in over node:sqlite
const sqlite = new DatabaseSync(":memory:");
const DB = {
  prepare(sql) {
    // Compile lazily, like D1 does, so a batch can create a table and then
    // an index on it.
    const stmt = () => sqlite.prepare(sql);
    let args = [];
    const o = {
      bind(...a) { args = a; return o; },
      async first() { return stmt().get(...args) ?? null; },
      async all() { return { results: stmt().all(...args) }; },
      async run() { const r = stmt().run(...args); return { meta: { changes: Number(r.changes) } }; },
      _run() { stmt().run(...args); },
    };
    return o;
  },
  async batch(list) { list.forEach((s) => s._run()); },
};

const worker = (await import("./worker.js")).default;
const env = {
  DB, PAYSTACK_SECRET_KEY: "sk_test", PAYSTACK_PLAN_CODE: "PLN_x", ADMIN_TOKEN: "adm",
  TELEGRAM_BOT_TOKEN: "bot_test_token", TELEGRAM_CHAT_ID: "-1001234567890"
};
const ctx = { waitUntil: (promise) => pendingNotifications.push(promise) };
const flushNotifications = async () => { await Promise.all(pendingNotifications.splice(0)); };
const call = (path, init) => worker.fetch(new Request("https://feed.example.com" + path, init), env, ctx);
const post = (path, body, headers = {}) => call(path, {
  method: "POST",
  headers: { "content-type": "application/json", ...headers },
  body: JSON.stringify(body)
});
const ID = "a1b2c3d4e5f60718293a4b5c6d7e8f90";
const ID2 = "ffeeddccbbaa00998877665544332211";

// 1. config: naira price, local equivalent, no secrets
let j = await (await call("/sub/config?cur=USD")).json();
assert.equal(j.price_ngn, 2000);
assert.equal(j.price_display, "₦2,000");
assert.equal(j.local_display, "$1.30");
assert.equal(j.recurring, true);
j = await (await call("/sub/config?cur=NGN")).json();
assert.equal(j.local_display, null);
j = await (await call("/sub/config?cur=ZZZ")).json();
assert.equal(j.local_display, null);

// 2. status of a stranger is inactive; bad ids rejected
j = await (await call(`/sub/status?install=${ID}`)).json();
assert.equal(j.active, false);
assert.equal((await call("/sub/status?install=x")).status, 400);

// 3. start: validates, builds the right Paystack request
assert.equal((await post("/sub/start", { install_id: ID, email: "bad" })).status, 400);
j = await (await post("/sub/start", { install_id: ID, email: "Ada@Example.com", recurring: false }, { "x-platform": "windows" })).json();
await flushNotifications();
assert.match(telegramMessages.at(-1).text, /Premium subscription checkout requested/);
assert.match(telegramMessages.at(-1).text, /Windows PC app/);
assert.equal(telegramMessages.at(-1).chat_id, "-1001234567890");
assert.equal(j.authorization_url, "https://checkout.paystack.com/x");
assert.equal(initBody.amount, 200000);
assert.equal(initBody.currency, "NGN");
assert.equal(initBody.email, "ada@example.com");
assert.equal(initBody.metadata.install_id, ID);
assert.equal(initBody.callback_url, "https://feed.example.com/sub/done");
assert.equal(initBody.plan, undefined);
const ref1 = j.reference;

// 4. verify grants ~31 days, and is idempotent (webhook + verify for one payment)
j = await (await call(`/sub/verify?reference=${ref1}`)).json();
assert.equal(j.status, "success"); assert.equal(j.active, true);
const first = j.expires_at;
assert.ok(first - Date.now() > 30.9 * 86400000 && first - Date.now() < 31.1 * 86400000);
j = await (await call(`/sub/verify?reference=${ref1}`)).json();
assert.equal(j.expires_at, first);
const body = JSON.stringify({ event: "charge.success", data: txs.get(ref1) });
let sig = createHmac("sha512", "sk_test").update(body).digest("hex");
assert.equal((await call("/sub/webhook", { method: "POST", body, headers: { "x-paystack-signature": sig } })).status, 200);
j = await (await call(`/sub/status?install=${ID}`)).json();
assert.equal(j.expires_at, first, "same payment must not extend twice");
assert.equal(j.active, true);

// 5. webhook: bad signature rejected
assert.equal((await call("/sub/webhook", { method: "POST", body, headers: { "x-paystack-signature": "nope" } })).status, 401);

// 6. automatic renewal (no metadata) is matched by e-mail and stacks on top
txs.set("RENEW1", { status: "success", reference: "RENEW1", currency: "NGN", amount: 200000, customer: { email: "ada@example.com" }, metadata: {} });
const rb = JSON.stringify({ event: "charge.success", data: txs.get("RENEW1") });
sig = createHmac("sha512", "sk_test").update(rb).digest("hex");
await call("/sub/webhook", { method: "POST", body: rb, headers: { "x-paystack-signature": sig } });
j = await (await call(`/sub/status?install=${ID}`)).json();
assert.equal(j.expires_at, first + 31 * 86400000);

// 7. under-paid / wrong-currency / failed payments never grant
txs.set("CHEAP01", { status: "success", reference: "CHEAP01", currency: "NGN", amount: 100, customer: { email: "x@y.com" }, metadata: { install_id: ID2 } });
j = await (await call("/sub/verify?reference=CHEAP01")).json();
assert.equal(j.status, "failed");
txs.set("USD0001", { status: "success", reference: "USD0001", currency: "USD", amount: 900000, customer: { email: "x@y.com" }, metadata: { install_id: ID2 } });
assert.equal((await (await call("/sub/verify?reference=USD0001")).json()).status, "failed");
txs.set("ABAND01", { status: "abandoned", reference: "ABAND01", currency: "NGN", amount: 200000, customer: { email: "x@y.com" }, metadata: { install_id: ID2 } });
assert.equal((await (await call("/sub/verify?reference=ABAND01")).json()).status, "failed");
assert.equal((await (await call(`/sub/status?install=${ID2}`)).json()).active, false);
assert.equal((await call("/sub/verify?reference=a")).status, 400);

// 8. restore on a new phone: needs matching e-mail + a real reference
assert.equal((await post("/sub/restore", { install_id: ID2, email: "other@example.com", reference: ref1 })).status, 404);
j = await (await post("/sub/restore", { install_id: ID2, email: "ada@example.com", reference: ref1 })).json();
assert.equal(j.active, true);
assert.equal((await (await call(`/sub/status?install=${ID2}`)).json()).active, true);

// 9. recurring checkout sends the plan
await post("/sub/start", { install_id: ID, email: "ada@example.com", recurring: true });
assert.equal(initBody.plan, "PLN_x");

// 10. admin: protected, grants days for WhatsApp payers, revokes with 0
assert.equal((await call("/sub/admin?token=wrong")).status, 403);
const ID3 = "00112233445566778899aabbccddeeff";
const form = (o) => ({ method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(o).toString() });
let page = await (await call("/sub/admin", form({ token: "adm", install_id: ID3, days: "30" }))).text();
assert.match(page, /Premium until/);
assert.match(page, /Decoder number: [0-9]{10}/);
assert.equal((await (await call(`/sub/status?install=${ID3}`)).json()).active, true);
// Top up by the current Decoder number: preserve the number and both
// registered devices; a third device must remain blocked.
const codeMatch = /Decoder number: ([0-9]{10})/.exec(page);
assert.ok(codeMatch, "admin grant issues a Decoder number");
const stableCode = codeMatch[1];
const deviceA = "11112222333344445555666677778888";
const deviceB = "aaaabbbbccccddddeeeeffff00001111";
const deviceC = "99998888777766665555444433332222";
const validateDecoder = async (code, device_id) =>
  (await post("/receiver/decoder/validate", { code, device_id })).json();
assert.equal((await validateDecoder(stableCode, deviceA)).valid, true);
assert.equal((await validateDecoder(stableCode, deviceB)).valid, true);
assert.equal((await validateDecoder(stableCode, deviceC)).limit_reached, true);
const expiryBeforeTopup = (await (await call(`/sub/status?install=${ID3}`)).json()).expires_at;
page = await (await call("/sub/admin", form({ token: "adm", install_id: stableCode, days: "30" }))).text();
assert.match(page, new RegExp(`Decoder number: ${stableCode}`), "active top-up preserves the same Decoder number");
const expiryAfterTopup = (await (await call(`/sub/status?install=${ID3}`)).json()).expires_at;
assert.equal(expiryAfterTopup, expiryBeforeTopup + 30 * 86400000, "top-up adds days to the existing expiry");
assert.equal((await validateDecoder(stableCode, deviceA)).valid, true, "first device survives top-up");
assert.equal((await validateDecoder(stableCode, deviceB)).valid, true, "second device survives top-up");
assert.equal((await validateDecoder(stableCode, deviceC)).limit_reached, true, "top-up does not add device slots");

// After expiry, a new Decoder number is issued with a fresh two-device allowance.
sqlite.prepare("UPDATE decoder_codes SET expires_at=? WHERE owner_id=?").run(Date.now()-1000, ID3);
page = await (await call("/sub/admin", form({ token: "adm", install_id: stableCode, days: "30" }))).text();
const renewedCodeMatch = /Decoder number: ([0-9]{10})/.exec(page);
assert.ok(renewedCodeMatch);
assert.notEqual(renewedCodeMatch[1], stableCode, "expired Decoder number is replaced after reactivation");
assert.equal((await validateDecoder(renewedCodeMatch[1], deviceC)).valid, true, "new number starts a fresh device allowance");

await call("/sub/admin", form({ token: "adm", install_id: ID3, days: "0" }));
assert.equal((await (await call(`/sub/status?install=${ID3}`)).json()).active, false);
assert.equal((await call("/sub/admin?token=adm")).status, 200);

// 11. shared three-title movie trial (app account + receiver visitor)
const TRIAL_APP = "1234567890abcdef1234567890abcdef";
const TRIAL_DEVICE = "abcdef1234567890abcdef1234567890";
const TRIAL_GUEST = "abcdefabcdefabcdefabcdefabcdefab";
for (const [id, prefix] of [[TRIAL_APP, "/sub/movie-access"], [TRIAL_GUEST, "/sub/movie-access-guest"], [TRIAL_DEVICE, "/receiver/movie-access"]]) {
  const payload = key => prefix.indexOf("/sub/") === 0
    ? { install_id: id, movie_key: key, action: "play" }
    : { device_id: id, movie_key: key, action: "play" };
  for (const key of ["movie:one", "movie:two", "movie:three"]) {
    j = await (await post(prefix, payload(key))).json();
    assert.equal(j.allowed, true);
  }
  j = await (await post(prefix, payload("movie:four"))).json();
  assert.equal(j.allowed, false);
  const repeat = prefix.indexOf("/sub/") === 0
    ? { install_id: id, movie_key: "movie:one", action: "alternate" }
    : { device_id: id, movie_key: "movie:one", action: "alternate" };
  assert.equal((await (await post(prefix, repeat)).json()).allowed, true);
  const fourthDownload = prefix.indexOf("/sub/") === 0
    ? { install_id: id, movie_key: "movie:four", action: "download" }
    : { device_id: id, movie_key: "movie:four", action: "download" };
  assert.equal((await (await post(prefix, fourthDownload)).json()).allowed, false);
}

// 12. Free casting is limited to five successful cast sessions per account/install.
for (const [id, path] of [
  ["1234567890abcdef1234567890abcdef", "/sub/cast-access"],
  ["abcdefabcdefabcdefabcdefabcdefab", "/sub/cast-access-guest"],
]) {
  // Opening the device picker / checking the allowance never consumes a use.
  j = await (await post(path, { install_id: id, action: "check" })).json();
  assert.equal(j.allowed, true);
  assert.equal(j.used, 0);
  assert.equal(j.remaining, 5);
  for (let n = 1; n <= 5; n++) {
    j = await (await post(path, { install_id: id, action: "consume" })).json();
    assert.equal(j.allowed, true);
    assert.equal(j.used, n);
    assert.equal(j.remaining, 5 - n);
  }
  j = await (await post(path, { install_id: id })).json();
  assert.equal(j.allowed, false);
  assert.equal(j.used, 5);
  assert.equal(j.remaining, 0);
}

// Premium accounts bypass the free casting counter.
await call("/sub/admin", form({ token: "adm", install_id: ID3, days: "30" }));
for (let n = 0; n < 7; n++) {
  j = await (await post("/sub/cast-access", { install_id: ID3 })).json();
  assert.equal(j.allowed, true);
  assert.equal(j.premium, true);
}

// 13. Decoder numbers are server-issued and stop working when Premium expires.
const decoderGrant = await (await call("/sub/admin", form({ token: "adm", install_id: ID3, days: "30" }))).text();
assert.match(decoderGrant, /Premium until/);
assert.match(decoderGrant, /Decoder number: [0-9]{10}/);
j = await (await post("/sub/decoder/issue", { install_id: ID3 }, { "x-platform": "android" })).json();
await flushNotifications();
assert.match(telegramMessages.at(-1).text, /Premium Decoder activation requested/);
assert.match(telegramMessages.at(-1).text, /Deeprowss App/);
assert.equal(j.active, true);
assert.match(j.code, /^\d{10}$/);
const decoderCode = j.code;
j = await (await post("/receiver/decoder/validate", { code: decoderCode })).json();
assert.equal(j.valid, true);
assert.equal("owner_id" in j, false);
// One Decoder number can be paired with two devices, but not a third.
const DEVICE_A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const DEVICE_B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const DEVICE_C = "cccccccccccccccccccccccccccccccc";
j = await (await post("/receiver/decoder/validate", { code: decoderCode, device_id: DEVICE_A })).json();
assert.equal(j.valid, true);
j = await (await post("/receiver/decoder/validate", { code: decoderCode, device_id: DEVICE_B })).json();
assert.equal(j.valid, true);
let limited = await post("/receiver/decoder/validate", { code: decoderCode, device_id: DEVICE_C });
assert.equal(limited.status, 403);
assert.equal((await limited.json()).limit_reached, true);
// Admin can top up an existing subscription by entering its Decoder number.
// The existing code remains valid and its expiry is extended, not replaced.
const beforeTopup = await (await call("/receiver/sub/status?device=" + ID3)).json();
page = await (await call("/sub/admin", form({ token: "adm", install_id: decoderCode, days: "30" }))).text();
assert.match(page, /Premium until/);
const afterTopup = await (await call("/receiver/sub/status?device=" + ID3)).json();
assert.ok(afterTopup.expires_at > beforeTopup.expires_at + 29 * 86400000);
j = await (await post("/receiver/decoder/validate", { code: decoderCode, device_id: DEVICE_A })).json();
assert.equal(j.valid, true);
assert.equal(j.expires_at, afterTopup.expires_at);
// A renewal before expiry keeps the same code valid and extends its expiry.
txs.set("DECODERRENEW", {
  status: "success", reference: "DECODERRENEW", currency: "NGN", amount: 200000,
  customer: { email: "decoder@example.com" }, metadata: { install_id: ID3, period: "month" }
});
j = await (await call("/sub/verify?reference=DECODERRENEW")).json();
assert.equal(j.status, "success");
assert.equal((await (await post("/receiver/decoder/validate", { code: decoderCode })).json()).valid, true);
await call("/sub/admin", form({ token: "adm", install_id: ID3, days: "0" }));
j = await (await post("/receiver/decoder/validate", { code: decoderCode })).json();
assert.equal(j.valid, false);
// Resubscribing after expiry/revocation issues a different Decoder number.
await call("/sub/admin", form({ token: "adm", install_id: ID3, days: "30" }));
j = await (await post("/sub/decoder/issue", { install_id: ID3 })).json();
assert.equal(j.active, true);
assert.notEqual(j.code, decoderCode);
assert.equal((await (await post("/receiver/decoder/validate", { code: j.code })).json()).valid, true);

// 13. A receiver-only visitor can subscribe and receive a fresh Decoder number.
const RECEIVER_PAID = "fedcba0987654321fedcba0987654321";
j = await (await post("/receiver/sub/start", { install_id: RECEIVER_PAID, email: "tv@example.com", period: "year", recurring: false })).json();
await flushNotifications();
assert.match(telegramMessages.at(-1).text, /Premium subscription checkout requested/);
assert.match(telegramMessages.at(-1).text, /Website \/ TV receiver/);
assert.equal(initBody.metadata.install_id, RECEIVER_PAID);
assert.equal(initBody.metadata.period, "year");
assert.equal(initBody.amount, 2000000);
const receiverRef = j.reference;
j = await (await call("/receiver/sub/verify?reference=" + encodeURIComponent(receiverRef))).json();
assert.equal(j.status, "success");
j = await (await post("/receiver/decoder/issue", { device_id: RECEIVER_PAID })).json();
assert.equal(j.active, true);
assert.match(j.code, /^\d{10}$/);
assert.equal((await (await call("/receiver/sub/status?device=" + RECEIVER_PAID)).json()).active, true);
assert.equal((await (await post("/receiver/decoder/validate", { code: j.code })).json()).valid, true);

// 14. Ad-free token requests notify Telegram without changing the response.
const TOKEN_REQUEST_ID = "aa11223344556677889900aabbccddeeff";
j = await (await post("/sub/token/request", {
  install_id: TOKEN_REQUEST_ID, contact: "@deeprowss_user", days: 30, currency: "NGN"
}, { "x-platform": "android-tv" })).json();
await flushNotifications();
assert.equal(j.state, "pending");
assert.match(telegramMessages.at(-1).text, /Ad-free access token requested/);
assert.match(telegramMessages.at(-1).text, /Android TV/);

// 15. not set up: config still answers, the rest says 503; feed unaffected
const bare = (p) => worker.fetch(new Request("https://f.example.com" + p), {}, ctx);
assert.equal((await bare("/sub/config")).status, 200);
assert.equal((await (await bare("/sub/config")).json()).available, false);
assert.equal((await bare(`/sub/status?install=${ID}`)).status, 503);

console.log("subscription tests passed");
