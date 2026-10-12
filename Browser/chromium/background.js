// Grab with Cylindarr: the toolbar button and its shortcut grab the tab, the
// right-click menu grabs a link without opening it, and a YouTube channel or
// playlist link can be followed. The server's address and key are in
// chrome.storage.local, set on the options page.
import { call, feedback, followPatterns } from "./grab.js";

async function pairing() {
  const { server, key } = await chrome.storage.local.get(["server", "key"]);
  return server && key ? { server, key } : null;
}

async function show(tabId, fb) {
  const where = tabId ? { tabId } : {};
  await chrome.action.setBadgeBackgroundColor({ ...where, color: fb.colour });
  await chrome.action.setBadgeText({ ...where, text: fb.badge });
  await chrome.action.setTitle({ ...where, title: fb.title });
  setTimeout(() => {
    chrome.action.setBadgeText({ ...where, text: "" });
    chrome.action.setTitle({ ...where, title: "Grab with Cylindarr" });
  }, 5000);
}

// Follow offers waiting on a notification's button, by notification id.
const offers = new Map();

async function grab(url, tabId) {
  const p = await pairing();
  if (!p) {
    chrome.runtime.openOptionsPage();
    return;
  }
  if (!url || !/^https?:/.test(url)) {
    await show(tabId, { badge: "!", colour: "#c0263b", title: "There's no web link to grab here." });
    return;
  }
  await chrome.action.setBadgeText({ ...(tabId ? { tabId } : {}), text: "…" });
  let fb;
  try {
    const { status, body } = await call(p, "POST", "grabs", { url });
    fb = feedback(status, body);
  } catch (e) {
    fb = { badge: "!", colour: "#c0263b", title: `Couldn't reach Cylindarr at ${p.server}.`, follow: null };
  }
  await show(tabId, fb);
  if (fb.follow) offerFollow(fb.title, fb.follow.url);
  else if (fb.badge === "!") note("Not grabbed", fb.title);
}

function note(title, message, buttons) {
  const id = "cyl-" + Date.now();
  chrome.notifications.create(id, { type: "basic", iconUrl: "icons/icon-128.png", title, message, buttons, priority: 0 });
  return id;
}

function offerFollow(message, url) {
  const id = note("Follow on Cylindarr?", message, [{ title: "Follow" }]);
  offers.set(id, url);
}

async function follow(url) {
  const p = await pairing();
  if (!p) return chrome.runtime.openOptionsPage();
  try {
    const { status, body } = await call(p, "POST", "subscriptions", { url });
    if (status === 201) note("Following " + body.name, body.message);
    else note("Not followed", (body && body.reason) || `Cylindarr answered ${status}.`);
  } catch {
    note("Not followed", `Couldn't reach Cylindarr at ${p.server}.`);
  }
}

chrome.runtime.onInstalled.addListener(async (details) => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: "grab-link", title: "Grab with Cylindarr", contexts: ["link"] });
    chrome.contextMenus.create({ id: "grab-page", title: "Grab This Page with Cylindarr", contexts: ["page", "video"] });
    chrome.contextMenus.create({ id: "follow-link", title: "Follow on Cylindarr", contexts: ["link"], targetUrlPatterns: followPatterns });
  });
  if (details.reason === "install" && !(await pairing())) chrome.runtime.openOptionsPage();
});

chrome.action.onClicked.addListener((tab) => grab(tab.url, tab.id));

chrome.commands.onCommand.addListener(async (command, tab) => {
  if (command !== "grab-tab") return;
  const t = tab || (await chrome.tabs.query({ active: true, currentWindow: true }))[0];
  if (t) grab(t.url, t.id);
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "grab-link") grab(info.linkUrl, tab && tab.id);
  if (info.menuItemId === "grab-page") grab(info.pageUrl, tab && tab.id);
  if (info.menuItemId === "follow-link") follow(info.linkUrl);
});

chrome.notifications.onButtonClicked.addListener((id) => {
  const url = offers.get(id);
  offers.delete(id);
  chrome.notifications.clear(id);
  if (url) follow(url);
});
