# Troubleshooting

Start with the overview. The access line at the top says whether YouTube is answering, the counts say how much is waiting or needs you, and each video that needs you carries its reason.

## The journal

Everything Cylindarr does is one line in the journal: a verb, what it was done to, the outcome, and a detail. The Journal page shows it with filters, and the same lines are the container's log:

```sh
docker logs -f cylindarr
```

```
17:40:02  poll      subscription "Technology Connections"             ok       1 new, 1 wanted: 0KoeY54M5VA
17:40:31  fetch     video        "0KoeY54M5VA"                        ok       anonymous
17:47:10  encode    video        "0KoeY54M5VA"                        ok       HEVC with Quick Sync in 6m 38s, 3 cuts
17:47:11  place     episode      "Technology Connections"             ok       s2026e092401 - Engines haven't been fully mechanical in decades [0KoeY54M5VA].mp4, 3 SponsorBlock cuts
17:47:12  notify    server       "plex"                               ok       refreshed /data/youtube/Shows/Technology Connections
```

The columns are fixed, so `docker logs cylindarr | grep failed` or `grep 'encode '` does what you would expect. Passwords, tokens, and cookie paths are replaced with `<redacted>` before anything is written.

## Nothing is downloading

Check in this order:

1. **Is fetching on?** The overview says so when "Fetch wanted videos" is off in settings.
2. **Is the queue paused?** The overview shows a red banner with the reason and until when. Three bot checks in a row, a rate limit, or a disk below the free-space floor pause it. **Resume fetching** resumes at once, but if YouTube is still refusing, it will pause again.
3. **Is anything wanted?** New subscriptions start 30 days back, so a channel that has not posted in a month has nothing to fetch. The subscription's page lists every video it has seen and why each was skipped.
4. **Is the access check passing?** If extraction fails, see [Reaching YouTube](youtube-access.md).

## A video needs you

Its reason is on the overview. The common ones:

| Reason | What to do |
|---|---|
| Age-restricted, and the cookies' account cannot see it | Upload cookies from an age-verified account, then Retry now |
| Members only | Skip it. Cylindarr does not download members-only videos |
| Removed from YouTube, private, not available in this country | Nothing to be done; Skip clears it |
| Deferred too many times | It met the bot check or a network error over and over. Fix the access problem, then Retry now |
| yt-dlp failed in a way Cylindarr does not recognise | The detail carries yt-dlp's last lines. Often an update fixes it: press **Update yt-dlp**, then Retry now. If not, please open an issue with the lines |
| Encoding failed | The detail carries ffmpeg's last lines. See below |
| The encode plays for the wrong length | The encode stopped short; the video is not placed. Retry now; if it repeats, try another encoder |

## Every download meets the bot check

Your address is probably flagged. The access check fails with "bot-check", with and without cookies. More retries make it worse. See [Proxies](youtube-access.md#proxies). Before that, check the PO token provider is up (the access line says so) and that cookies, if you use them, pass the signed-in check.

## Encoding fails

- **`Error initializing an internal MFX session`, or `No VA display found`**: the GPU is not reachable from the container. Check `/dev/dri` is passed in and the container's user is in the group that owns the render node (`group_add` in the compose file). `docker exec cylindarr ls -l /dev/dri` shows the nodes and their group.
- **Quick Sync on older Intel graphics**: the journal shows the low-power mode being refused and the default mode tried. If the default mode fails too, the GPU may not encode HEVC at all; choose VA-API or the CPU.
- **NVENC: `Cannot load libnvidia-encode.so`**: the NVIDIA Container Toolkit is not giving the container the video capability. See [Encoding](encoding.md#passing-the-gpu-in).
- **The CPU is too slow**: choose "Do not encode" on the settings page.

## Plex or Jellyfin does not show new episodes

The journal's `notify` lines say whether the server answered.

- **A 401**: the token or API key is wrong.
- **Plex answers but nothing appears**: the section id may be the wrong library, or Plex sees the library at a different path (set "Plex sees the library at" on the settings page).
- **Jellyfin answers but nothing appears**: the path mapping. Jellyfin is told the file's path as Jellyfin sees it; if its container mounts the library elsewhere, set "Jellyfin sees the library at".
- **The show appears with the wrong name or no metadata**: the library is not reading NFO files. See [Media servers](media-servers.md).

## Permission denied

The container runs as `PUID:PGID` from `.env`. That user needs write access to the library folder and to `data/`. See [Permissions](install.md#permissions).

## If the database is lost

Everything on disk is safe: every file carries its YouTube id, and `cylindarr-subscriptions.json` at the library root lists every subscription with its rules. What is lost is Cylindarr's record of which videos it already placed. Rebuilding that record from the files is planned but not built yet, so for now: switch off fetching, follow the subscriptions again, set each one's cutoff to today, and switch fetching back on. Nothing already on disk is then downloaded a second time.

## Asking for help

Open an issue with the version (at the bottom of every page), what you expected, what happened, and the journal lines around it.
