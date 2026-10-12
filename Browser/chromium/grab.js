// The parts of the extension that decide things, kept free of the chrome.*
// APIs so `node --test` runs them (grab.test.js).

/** `cylindarr://pair?url=…&key=…` from Cylindarr's settings page. */
export function parsePairingLink(text) {
  const t = (text || "").trim();
  const m = t.match(/^cylindarr:\/\/pair\?(.*)$/);
  if (!m) return null;
  const q = new URLSearchParams(m[1]);
  const server = q.get("url");
  const key = q.get("key");
  if (!server || !key || !/^https?:\/\//.test(server)) return null;
  return { server: server.replace(/\/+$/, ""), key };
}

/** An address typed by hand: `nas.local:8295` means `http://nas.local:8295`. */
export function normaliseAddress(text) {
  let t = (text || "").trim().replace(/\/+$/, "");
  if (!t) return null;
  if (!/^https?:\/\//.test(t)) t = "http://" + t;
  try {
    const u = new URL(t);
    return u.origin + u.pathname.replace(/\/+$/, "");
  } catch {
    return null;
  }
}

/** The origin pattern the extension asks permission for. */
export function originPattern(server) {
  return new URL(server).origin + "/*";
}

/**
 * What the toolbar button shows for an answer: a badge for a few seconds and
 * the server's sentence as its tooltip. A YouTube channel or playlist also
 * offers Follow, in a notification.
 */
export function feedback(status, body) {
  if (status === 401) return { badge: "!", colour: "#c0263b", title: "Cylindarr didn't accept the key. Pair again on the options page.", follow: null };
  if (!body || !body.outcome) {
    const reason = body && body.reason ? body.reason : `Cylindarr answered ${status}.`;
    return { badge: "!", colour: "#c0263b", title: reason, follow: null };
  }
  switch (body.outcome) {
    case "queued":
    case "already":
      return { badge: "✓", colour: "#2f6f45", title: body.message, follow: null };
    case "followable":
      return { badge: "?", colour: "#3d4a8f", title: body.message, follow: body.follow || null };
    default:
      return { badge: "!", colour: "#c0263b", title: body.message, follow: null };
  }
}

/** Links that name a YouTube channel or playlist, for the Follow menu item. */
export const followPatterns = [
  "*://*.youtube.com/@*",
  "*://*.youtube.com/channel/*",
  "*://*.youtube.com/c/*",
  "*://*.youtube.com/user/*",
  "*://*.youtube.com/playlist*",
];

export async function call(pairing, method, path, body, fetchImpl = fetch) {
  const res = await fetchImpl(pairing.server + "/api/v1/" + path, {
    method,
    headers: { "X-Api-Key": pairing.key, "Content-Type": "application/json", Accept: "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try {
    json = await res.json();
  } catch {
    json = null;
  }
  return { status: res.status, body: json };
}
