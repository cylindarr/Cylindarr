# Apps and the browser extension

Cylindarr has a share extension for iPhone and Mac and an extension for Chromium browsers (Chrome, Arc, Brave, Edge). Each sends a link to your server in one or two taps, and the server files it under `Grabs` as a film. A grab can be any page yt-dlp can download a video from, not only YouTube.

## What each one does

- **iPhone.** Share a video from Safari, the YouTube app, or any app that shares a link, and choose **Grab with Cylindarr**. A card says what happened and closes itself. The same action is in Shortcuts as **Grab with Cylindarr**, so it can run from the Action button or Back Tap. The app lists recent grabs and their state, and can retry one that failed.
- **Mac.** The same share item, in every app's share menu, and **Services ▸ Grab with Cylindarr** on a selected link. The app's window lists recent grabs; **File ▸ Grab Link from Clipboard** (⇧⌘V) grabs what you copied, and dropping a link on the window grabs it too.
- **Chromium browsers.** The toolbar button grabs the video in the tab, **Alt+Shift+G** does the same, and right-clicking any link offers **Grab with Cylindarr** without opening it. Right-clicking a YouTube channel or playlist link offers **Follow on Cylindarr**.

Sharing a YouTube channel or playlist offers to follow it as a show, starting 30 days back. A playlist or channel on any other site is refused: grabs take one video, and only YouTube's can be followed.

## Pairing

Every app and the extension need the server's address and its API key. Both are on the settings page under **Connect an app**, with a QR code and a pairing link that carry them together.

- **iPhone.** Scan the QR code with the Camera app and confirm.
- **Mac.** Click **Open in the app** on the settings page, or paste the pairing link into the app's Settings (⌘,).
- **Browser.** Copy the pairing link, paste it on the extension's options page, and press Connect. The browser then asks for permission to reach that one address.

The key lets whoever holds it queue downloads and follow channels. **Make a new key** on the settings page replaces it, and every app and extension stops working until it is paired again. `CYLINDARR_API_KEY` fixes the key, for example to keep it in a secrets file.

The address the settings page shows is the one you opened it at. If the apps reach Cylindarr by another name (a reverse proxy, a Tailscale name), set `CYLINDARR_PUBLIC_URL` and the page uses that.

## Plain HTTP and the local network

The apps allow plain HTTP, because a Cylindarr server is usually on a home network. iOS asks once for permission to reach devices on the local network; say yes. HTTPS works the same way and is the better choice for anything reached across the internet: put Cylindarr behind your reverse proxy, or use `tailscale serve`.

## What happens after a grab

The server answers at once. A YouTube video is queued under its id. A link from another site is queued straight away while the server asks yt-dlp what is there, which takes a few seconds; anything that is audio only (SoundCloud, Bandcamp, a podcast page), a playlist, or not something yt-dlp can download is refused at that point with the reason, and nothing is downloaded.

Grabs go to the front of the queue, ahead of subscription videos. While YouTube's bot check has paused downloads, YouTube grabs wait, but grabs from other sites go on. With an [ntfy](https://ntfy.sh) topic set, every grab that lands in the library, or fails, sends a notification.

Grabs from other sites are downloaded signed out. A site that wants an account (Vimeo, for example, now refuses signed-out downloads) fails with **the site wants an account**.

## Installing them

The apps are built from `Apple/` in this repository with Xcode and XcodeGen; see [Development](development.md#the-apple-apps). The extension is in `Browser/chromium/`: open `chrome://extensions`, turn on Developer mode, choose **Load unpacked**, and pick that folder.

## The API

The apps use a small JSON API that anything else can use too. Every call is under `/api/v1/` and sends the key as `X-Api-Key`.

| Call | Does |
|---|---|
| `GET /api/v1/status` | Version, whether fetching is on, why YouTube downloads are paused if they are, grabs waiting |
| `POST /api/v1/grabs` with `{"url": "…"}` | Grabs a link. Answers with an `outcome` (`queued`, `already`, `followable`, `refused`), a `message` and the `grab` |
| `GET /api/v1/grabs?limit=50` | Recent grabs, newest first |
| `GET /api/v1/grabs/<key>` | One grab |
| `POST /api/v1/grabs/<key>/retry` | Tries a grab again |
| `POST /api/v1/subscriptions` with `{"url": "…"}` | Follows a YouTube channel or playlist |

```sh
curl -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
     -d '{"url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"}' http://cylindarr:8295/api/v1/grabs
```

The request and response types are `CylindarrAPI/` in this repository.
