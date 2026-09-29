# Installing

Cylindarr runs as a Docker container beside a small PO token provider. The [compose file](../compose.yaml) at the top of the repository runs both; this page explains what each part of it is for and what to change.

## What you need

- Docker with Compose, on `linux/amd64` or `linux/arm64`.
- A folder for the library that your media server can read. Cylindarr writes everything under it: `Shows/`, `Grabs/`, and its own `.cylindarr/staging/` for downloads in progress.
- A few hundred MB of memory while a video is encoding, and disk for the library. Cylindarr stops fetching when the library's disk has less than 50 GB free (a setting).
- Optionally, a GPU for encoding. See [Encoding](encoding.md).

The image carries yt-dlp, ffmpeg, and Deno (yt-dlp's JavaScript runtime). Nothing else needs installing on the host.

## The steps

```sh
git clone <this repository> cylindarr && cd cylindarr
cp .env.example .env
mkdir data
```

Edit `.env`:

| | |
|---|---|
| `PUID`, `PGID` | The user and group the container runs as. Use the ones that own your media library (`id` prints yours), so Plex and Jellyfin can read what Cylindarr writes |
| `TZ` | Your time zone, such as `America/New_York`. It sets the times shown on the pages and in the log |
| `CYLINDARR_PASSWORD` | A password every page asks for. See [Passwords and exposure](#passwords-and-exposure) |

Edit `compose.yaml`, at the line marked `CHANGE`: the left side of the library volume is the folder on your host. The right side, `/data/youtube`, is where Cylindarr sees it, and matches `CYLINDARR_LIBRARY`.

Then:

```sh
docker compose up -d --build
```

The first build takes a few minutes: it compiles Cylindarr and downloads yt-dlp, Deno, and the PO token plugin, each checked against its release's checksum. Open `http://<your server>:8295`.

## Permissions

Most first-run trouble with tools like this is permissions, so it is worth thirty seconds.

- **`data/`** holds the database, the cookies, and any yt-dlp the updater has fetched. Create it before the first start (`mkdir data`). If Docker creates it, it belongs to root and Cylindarr cannot write to it.
- **The library folder** must be writable by `PUID:PGID`. If it is not, the first download fails with a permission error in the journal. The fix is `sudo chown -R 1000:1000 /path/to/media/youtube` (with your IDs).
- **Files Cylindarr writes** belong to `PUID:PGID` and are readable by everyone, which is what Plex and Jellyfin need.

## Where the library lives

Keep `Shows/`, `Grabs/`, and staging under the one mount the compose file gives. Placing a finished download is then a rename, which is instant and never leaves a half-copied file. Two separate mounts would turn every placement into a copy, even on the same disk.

If your media server runs in its own container and mounts the same folder at a different path, that is fine: tell Cylindarr the mapping on the settings page. See [Media servers](media-servers.md).

## Passwords and exposure

With `CYLINDARR_PASSWORD` set, every page asks for a user name and password (the user name is `cylindarr` unless `CYLINDARR_USERNAME` says otherwise). Your browser remembers it. Two things stay open without it: `/health`, for health checks and dashboards, and the icons and style sheet.

Without a password, anyone who can reach the port can follow channels, delete episodes, and upload cookies for your Google account. That is the usual arrangement for arr apps on a home network, and it is fine when the port is reachable only from your LAN or a VPN. It is not fine on the internet. Either way, Cylindarr refuses a form posted from another website, so a page you visit cannot change it through your browser.

The login is HTTP Basic, which sends the password with every request. Over the internet, put Cylindarr behind a reverse proxy with HTTPS.

## Behind a reverse proxy

Cylindarr needs nothing special: proxy everything to port 8080 of the container (or 8295 on the host). With Caddy:

```
cylindarr.example.com {
    reverse_proxy localhost:8295
}
```

If the proxy does its own authentication (Authelia, Authentik, or your proxy's basic auth), you can leave `CYLINDARR_PASSWORD` blank. Set `CYLINDARR_PUBLIC_URL` to the address you reach it at, so notifications link back to the right page.

## Notifications

Cylindarr sends to [ntfy](https://ntfy.sh): paste a topic URL such as `https://ntfy.sh/your-topic` on the settings page. It sends when fetching pauses because YouTube started refusing, when your cookies stop working, and a week before they expire. Nothing is sent for ordinary progress; the journal has that.

## Updating

```sh
git pull
docker compose up -d --build
```

The database migrates itself on start. Back up `data/cylindarr.sqlite` first if you want a way back; with the container running, `sqlite3 data/cylindarr.sqlite ".backup data/cylindarr-backup.sqlite"` makes a consistent copy.

yt-dlp is updated separately, by Cylindarr itself, once a day. See [Reaching YouTube](youtube-access.md#keeping-yt-dlp-current).

## Running without Docker

Cylindarr is a Swift program and runs anywhere Swift 6 does, with yt-dlp, ffmpeg, and Deno on the path. [Development](development.md) shows how. The container is the supported way because it pins the versions of all of them.

## Next

Follow a channel ([Subscriptions](subscriptions.md)), then point your media server at the library ([Media servers](media-servers.md)). If you are coming from Pinchflat or TubeSync, read [Adopting a library](adopting.md) first: it starts with switching fetching off, so nothing is downloaded twice.
