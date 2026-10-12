// node --test Browser/chromium
import { test } from "node:test";
import assert from "node:assert/strict";
import { call, feedback, normaliseAddress, originPattern, parsePairingLink } from "./grab.js";

test("the settings page's pairing link", () => {
  assert.deepEqual(parsePairingLink("cylindarr://pair?url=http://nas.local:8295&key=0123abcd"), { server: "http://nas.local:8295", key: "0123abcd" });
  assert.equal(parsePairingLink("https://nas.local:8295"), null);
  assert.equal(parsePairingLink("cylindarr://pair?url=ftp://x&key=k"), null);
});

test("an address typed by hand", () => {
  assert.equal(normaliseAddress("nas.local:8295/"), "http://nas.local:8295");
  assert.equal(normaliseAddress("https://cyl.example.com/sub/"), "https://cyl.example.com/sub");
  assert.equal(originPattern("http://nas.local:8295"), "http://nas.local:8295/*");
  assert.equal(normaliseAddress(""), null);
});

test("what the badge says for each answer", () => {
  assert.equal(feedback(202, { outcome: "queued", message: "Queued, next in line." }).badge, "✓");
  assert.equal(feedback(200, { outcome: "already", message: "Already in the library." }).badge, "✓");
  const f = feedback(422, { outcome: "followable", message: "That's a YouTube channel.", follow: { kind: "channel", url: "u" } });
  assert.equal(f.badge, "?");
  assert.deepEqual(f.follow, { kind: "channel", url: "u" });
  assert.equal(feedback(422, { outcome: "refused", message: "That isn't a link." }).badge, "!");
  assert.match(feedback(401, { error: true, reason: "Send the key" }).title, /key/);
  assert.equal(feedback(500, { error: true, reason: "Boom" }).title, "Boom");
});

test("a call carries the key", async () => {
  let seen;
  const fake = async (url, init) => { seen = { url, init }; return { status: 202, json: async () => ({ outcome: "queued" }) }; };
  const r = await call({ server: "http://nas.local:8295", key: "k1" }, "POST", "grabs", { url: "https://x" }, fake);
  assert.equal(r.status, 202);
  assert.equal(seen.url, "http://nas.local:8295/api/v1/grabs");
  assert.equal(seen.init.headers["X-Api-Key"], "k1");
  assert.equal(JSON.parse(seen.init.body).url, "https://x");
});
