# Configuration

Everything is set on the settings page and kept in the database, so changing a setting never means editing the compose file and recreating the container. The environment can also set most of them. A setting given by the environment wins over the page, and the page lists it as set by the environment so you know why a change does not stick.

## The settings page

### Library

| Setting | Default | What it does |
|---|---|---|
| Library root | `/library` | Where `Shows/`, `Grabs/`, and staging go, as the container sees it. The compose file sets it with `CYLINDARR_LIBRARY` |
| Subtitle languages | `en` | Comma-separated language codes (`en,de,pt-BR`). Blank for no subtitles |
| Pause fetching below | 50 GB free | Downloads wait while the library's disk has less free space than this |
| Poll every | 30 minutes | How often each subscription is checked for new uploads. At least 5 |
| Fetch wanted videos | on | Off keeps noticing new uploads and deciding about them, but downloads nothing. Useful while adopting, or to pause everything |

### Reaching YouTube

| Setting | Default | What it does |
|---|---|---|
| yt-dlp | `/app/bin/yt-dlp` | The yt-dlp binary. The daily update changes this to the version it installed |
| Update yt-dlp daily | on | See [Keeping yt-dlp current](youtube-access.md#keeping-yt-dlp-current) |
| PO token provider | blank | The provider's URL. The compose file sets `http://pot:4416` |
| Proxy for yt-dlp | blank | `socks5://user:password@host:1080` or `http://host:port`, for downloads only. See [Proxies](youtube-access.md#proxies) |

Cookies are uploaded on the same page. See [Cookies](youtube-access.md#cookies).

### Media servers

| Setting | What it does |
|---|---|
| Plex URL | `http://host.docker.internal:32400` when Plex is on the same host |
| Plex token | Your `X-Plex-Token`. Never shown again once saved |
| Plex TV section id, Plex Grabs section id | The libraries to refresh. Either may be blank |
| Plex sees the library at | A path mapping, when Plex's container mounts the library somewhere else |
| Jellyfin URL, Jellyfin API key | Also used for Emby |
| Jellyfin sees the library at | A path mapping, when Jellyfin's container mounts the library somewhere else |

[Media servers](media-servers.md) explains each.

### Notifications

An [ntfy](https://ntfy.sh) topic URL. Cylindarr posts when fetching pauses because YouTube refused, when the cookies stop working, and a week before they expire.

### Connect an app

The server's address, its API key, a QR code and a pairing link, for the [apps and the browser extension](apps.md#pairing). **Make a new key** replaces the key; everything paired with the old one has to be paired again.

### Encoding

The encoder and the quality number. See [Encoding](encoding.md). "Download the library again" queues every placed video to be downloaded and encoded again, which is what you want after changing the encoder or quality; each keeps its episode number and its current file until the new one is ready, and new uploads go first.

### Fixed values

Some things are deliberately not settings. Cylindarr downloads one video at a time, with a pause of one to three minutes between downloads, so a single address does not look like a scraper. New subscriptions start 30 days back unless you ask for the back catalogue.

## Environment variables

Only a few have to be in the environment, because they are needed before the database opens or they guard the pages:

| Variable | What it does |
|---|---|
| `CYLINDARR_DATA` | Where the database, cookies, and yt-dlp updates live. `/app/data` in the image |
| `CYLINDARR_PASSWORD` | Turns on the login. See [Passwords and exposure](install.md#passwords-and-exposure) |
| `CYLINDARR_USERNAME` | The login's user name. `cylindarr` by default |
| `CYLINDARR_PUBLIC_URL` | The address you reach Cylindarr at, such as `https://cylindarr.example.com`. Tapping a notification opens the page it is about, and the pairing code on the settings page carries it |
| `TZ` | The time zone for times on the pages and in the log |

These set a page setting and fix it there:

| Variable | Setting |
|---|---|
| `CYLINDARR_LIBRARY` | Library root |
| `CYLINDARR_YTDLP` | yt-dlp. Setting it also stops the daily update, since the binary is pinned |
| `CYLINDARR_POT_PROVIDER_URL` | PO token provider |
| `CYLINDARR_PROXY` | Proxy for yt-dlp |
| `CYLINDARR_PLEX_URL`, `CYLINDARR_PLEX_TOKEN` | Plex URL and token |
| `CYLINDARR_PLEX_SECTION`, `CYLINDARR_PLEX_GRABS_SECTION` | Plex's TV and Grabs section ids |
| `CYLINDARR_PLEX_PATH_MAP` | Plex's path mapping |
| `CYLINDARR_JELLYFIN_URL`, `CYLINDARR_JELLYFIN_KEY` | Jellyfin URL and API key |
| `CYLINDARR_JELLYFIN_PATH_MAP` | Jellyfin's path mapping |
| `CYLINDARR_NTFY_URL` | The ntfy topic |
| `CYLINDARR_ENCODER` | `auto`, `quicksync`, `vaapi`, `nvenc`, `software`, or `none` |
| `CYLINDARR_API_KEY` | The API key the apps and the browser extension send. Made at first start when not set |

Secrets (the Plex token, the Jellyfin key, a proxy password) are often easier to keep in an `.env` file than in the database; either works.

And two for development and unusual setups:

| Variable | What it does |
|---|---|
| `CYLINDARR_FFMPEG` | The ffmpeg binary, when it is not at `/usr/bin/ffmpeg` (ffprobe is expected beside it) |
| `CYLINDARR_SCHEDULER=off` | Runs the pages without polling, fetching, or the hourly checks |

## Where things are kept

| | |
|---|---|
| `data/cylindarr.sqlite` | Subscriptions, every decision about every video, retry times, and the journal |
| `data/cookies.txt` | The uploaded cookies, YouTube's and Google's only, readable by the container's user alone |
| `data/bin/` | yt-dlp versions the updater installed: the current one and the one before |
| `<library>/cylindarr-subscriptions.json` | Every subscription and its rules, rewritten after each change, as a record that survives losing the database |
| `<library>/.cylindarr/staging/` | Downloads in progress. Empty between downloads |
