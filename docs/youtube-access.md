# Reaching YouTube

YouTube does not want to be downloaded from, and it gets better at saying so every few weeks. No tool can promise it will keep working. What Cylindarr promises is that when it stops working you will know within the hour, you will know which piece broke, and nothing will be marked done that is not on disk.

## The pieces

| Piece | What it is for | Where it comes from |
|---|---|---|
| yt-dlp | Extracts and downloads the video | In the image, then updated daily by Cylindarr |
| Deno | yt-dlp solves YouTube's player JavaScript with it; without a JS runtime, formats go missing | In the image |
| PO token provider | YouTube asks for a "proof of origin" token that ties requests to a browser-like session; without one, the bot check comes sooner | The `pot` container in the compose file, with its yt-dlp plugin in the image |
| Cookies | A signed-in session, for age-restricted videos and for getting past a bot check | Optional; you upload them |

The overview's access line shows each piece: extraction ok or failed, the yt-dlp version, the PO token provider, the cookies, and whether downloads go direct or through a proxy. It is checked when Cylindarr starts, every hour after, and whenever you press **Check now**. The check asks yt-dlp to extract a long-lived public video without downloading it (YouTube's first video, "Me at the zoo"), which is exactly what a real download does first.

## How new videos are noticed

Each subscription is polled on the settings page's interval (30 minutes by default). A poll reads YouTube's public RSS feed for the channel or playlist, which lists the 15 newest videos and never meets the bot check. The feeds are unreliable (playlist feeds in particular answer with a 404 page much of the time and then work a minute later), so when a feed does not answer, the poll uses yt-dlp's flat listing of the 20 newest instead. A flat listing is one cheap request and, in practice, passes where full extraction is refused.

Only a download uses full extraction, which is the request the bot check watches. So polling a hundred subscriptions costs very little of YouTube's patience; downloading is what spends it.

## When YouTube says no

Every yt-dlp failure is sorted into a cause, and the cause decides what happens:

| Cause | What happens |
|---|---|
| Bot check ("Sign in to confirm you're not a bot") | The video waits and tries again after 1, 3, 12, then 24 hours. Three in a row pause the whole queue: at that point it is your address, not the videos, and retrying into it keeps the address flagged |
| Rate limited (HTTP 429) | The whole queue pauses for an hour |
| Stream refused (HTTP 403 on the video data) | Usually a stale yt-dlp or a missing PO token. The video waits 2, 6, then 24 hours while the updater catches up |
| Age-restricted | Tried again with cookies. If there are none, or the account cannot see it, it needs you |
| Members only | Skipped |
| Premiere, or live now | Waits until it has aired and its recording is ready |
| Removed, private, not available in your country | Needs you, with the reason |
| Network trouble | Tries again after 5 minutes, then longer |
| Anything unrecognised | Tries once more, then needs you, with yt-dlp's last lines attached |

While the queue is paused, the overview says why and until when, and polling carries on. When the pause runs out, Cylindarr runs the access check before trying a real video, and resumes only if it passes. **Resume fetching** on the overview resumes at once.

## PO tokens

The compose file runs [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider) on a private Docker network that only Cylindarr can reach. Keep it that way: versions before 2.0.0 had a remote code execution hole when reachable from the network, so the compose file pins 2.0.0, and the provider's port should never be published.

Without a provider everything still works, and the overview shows a warning that the bot check will come sooner.

## Cookies

Cookies make Cylindarr signed in, which gets it past age restrictions and often past a bot check. They are optional and used only when needed: every download is tried anonymously first, and again with cookies only when the failure is one cookies can fix. That keeps the account's footprint small.

**Use a separate Google account made for this**, not your own. An account that downloads can be flagged or suspended, and you do not want that to be the one with your mail on it. For age-restricted videos, the account has to be age-verified.

**Export them so they last.** A signed-in YouTube session rotates its cookies while it is open in a browser, and an exported copy stops working within days if you keep using that session. So:

1. Open a private (incognito) window and sign in to YouTube with the account.
2. Export `cookies.txt` from that window with a cookies.txt export extension, in Netscape format.
3. Close the private window without using YouTube in it again.

Upload the file on the settings page. Cylindarr checks that it is a signed-in session (it must contain `SAPISID`, `__Secure-3PSID`, and `LOGIN_INFO`), keeps only the YouTube and Google cookies from it, and runs a signed-in check at once: yt-dlp lists the account's subscriptions feed, which YouTube refuses without a live session. The settings page shows the result and the earliest expiry. The check runs again every hour, and ntfy tells you once when the cookies stop working and once when one is a week from expiring.

## Proxies

If YouTube has flagged your home address (every download meets the bot check, with and without cookies, and the access check fails), the fix is a different address, not more retries. Retrying into a flagged address is what keeps it flagged. The usual cause is a burst of downloads, such as another tool fetching a whole back catalogue in an afternoon. A flag goes with the address, so a new address from your ISP clears it; how long one lasts otherwise, YouTube does not say.

**Proxy for yt-dlp** on the settings page sends yt-dlp, and nothing else, through a proxy: `socks5://user:password@host:1080` or `http://host:port`. Feeds, SponsorBlock, artwork, and your media servers stay direct. A small SOCKS5 server at a friend's house or a second site works well. A VPN or datacenter address usually works worse than a home connection, because YouTube treats those addresses more harshly, which is also why the compose file does not put Cylindarr behind a VPN container.

The proxy's password is never shown on the settings page or written to the log.

## Keeping yt-dlp current

YouTube changes break yt-dlp every few weeks, and fixes ship within days. A tool whose yt-dlp stays at the version in its image stops working, which is how most abandoned downloaders die.

So once a day, Cylindarr checks yt-dlp's latest release. If there is a newer one, it downloads the binary for its platform, checks it against the release's published SHA-256 sums, and runs the access check with it. It switches to the new version only if the check passes; otherwise it stays where it is and the journal says why. It keeps the version before as well. **Update yt-dlp** on the overview does the same thing now.

If you would rather nothing in your container downloaded executables, switch off "Update yt-dlp daily". Setting `CYLINDARR_YTDLP` also pins it.

## Pacing

Cylindarr downloads one video at a time with a random pause of one to three minutes between them, and new subscriptions start 30 days back. That is slow on purpose. A human watching YouTube does not pull 700 videos in an afternoon, and an address that does gets flagged.
