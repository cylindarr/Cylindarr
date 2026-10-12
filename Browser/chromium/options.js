import { call, normaliseAddress, originPattern, parsePairingLink } from "./grab.js";

const $ = (id) => document.getElementById(id);
const status = (text, kind) => { $("status").textContent = text; $("status").className = kind || ""; };

chrome.storage.local.get(["server", "key"]).then(({ server, key }) => {
  if (server) $("server").value = server;
  if (key) $("key").value = key;
  if (server && key) status(`Paired with ${server}.`, "ok");
});

$("link").addEventListener("input", () => {
  const p = parsePairingLink($("link").value);
  if (p) { $("server").value = p.server; $("key").value = p.key; }
});

$("form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const server = normaliseAddress($("server").value);
  const key = $("key").value.trim();
  if (!server || !key) return status("Enter the address and the key, or paste the pairing link.", "bad");
  // Asked for this one server only, and only now, from the click.
  const granted = await chrome.permissions.request({ origins: [originPattern(server)] });
  if (!granted) return status("The extension needs permission to reach your server.", "bad");
  status("Checking…");
  try {
    const { status: code, body } = await call({ server, key }, "GET", "status");
    if (code === 401) return status("Cylindarr didn't accept that key.", "bad");
    if (code !== 200 || !body || !body.version) return status(`That address answered ${code}; is it Cylindarr?`, "bad");
    await chrome.storage.local.set({ server, key });
    status(`Paired with Cylindarr ${body.version} at ${server}.`, "ok");
  } catch {
    status(`Couldn't reach ${server}. If it is on a VPN such as Tailscale, is that connected?`, "bad");
  }
});
