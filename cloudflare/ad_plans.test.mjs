// Run: node --no-warnings cloudflare/ad_plans.test.mjs   (Node 22+)
// "Remove ads" plans priced per currency + the plan saved with a token request.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
globalThis.caches = { default: { match: async () => undefined, put: async () => {} } };
globalThis.fetch = async () => new Response(JSON.stringify({ rates: { EGP: 0.0345, USD: 0.00065, NGN: 1 } }));
const sqlite = new DatabaseSync(":memory:");
const DB = { prepare(sql){ const stmt=()=>sqlite.prepare(sql); let args=[]; const o={ bind(...a){args=a;return o;}, async first(){return stmt().get(...args)??null;}, async all(){return {results:stmt().all(...args)};}, async run(){const r=stmt().run(...args);return {meta:{changes:Number(r.changes)}};}, _run(){stmt().run(...args);} }; return o; }, async batch(l){l.forEach(s=>s._run());} };
const worker = (await import("./worker.js")).default;
const env = { DB, ADMIN_TOKEN: "adm" };
const call = (p, i) => worker.fetch(new Request("https://x.example" + p, i), env, { waitUntil(){} });
let j = await (await call("/sub/ad-plans?cur=EGP")).json();
console.log(JSON.stringify(j.plans.slice(0,3)), j.currency);
j = await (await call("/sub/ad-plans?cur=NGN")).json(); console.log(j.currency, j.plans[0]);
const A="a1b2c3d4e5f60718293a4b5c6d7e8f90";
let r = await call("/sub/token/request",{method:"POST",body:JSON.stringify({install_id:A,contact:"+20 100 000 0000",days:30,currency:"egp"})});
console.log(await r.json());
const html = await (await call("/sub/admin?token=adm")).text();
assert.ok(html.includes("Wants <b>30 days</b>"), "plan shown in admin");
console.log("ok");
