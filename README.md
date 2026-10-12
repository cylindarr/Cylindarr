<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/cylindarr-lockup-dark.svg">
    <img src="docs/images/cylindarr-lockup-light.svg" alt="Cylindarr" width="320">
  </picture>
</p>

<p align="center"><b>Channels in. Shows out.</b></p>

Cylindarr follows YouTube channels and playlists, and files what they post as TV shows for Plex, Jellyfin, and Emby.

You give it a channel. It notices new uploads, downloads them with yt-dlp, cuts away the sponsor segments, and puts each video in a show folder with an NFO, a thumbnail, and subtitles, named and numbered so your media server reads it as a series without a plugin. Then it tells Plex or Jellyfin the file is there. It sits beside Sonarr and Radarr and keeps their habits: a queue, rules per show, and a page that tells you what needs you.

It exists because YouTube has become actively hostile toward it's users and I wasn't going to take it any more. Unfortuantely the tools people used for this stopped moving. Pinchflat's last commit was in December 2025, while YouTube keeps changing what it takes to download a video. TubeArr's repository is gone. A YouTube downloader that does not keep up breaks within weeks. So Cylindarr is built around the assumption that YouTube _will_ push back, and around saying clearly when it has. Fuck those guys. It would be nice if content creators would put their stuff outside of YouTube's walled garden. This stuff belongs to the creators, not YouTube. There is no reason everything needs to be in this hostile monolith.

Cylindarr has a share extension for iPhone and Mac and an extension for Chromium browsers (Chrome, Arc, Brave, Edge). Each sends a link to your server in one or two taps, and the server files it under `Grabs` as a film. A grab can be any page yt-dlp can download a video from, not only YouTube.

I recommend using Tailscale for your infra and keeping this server inside it for your own convenience and safety.

## What it does

- **One subscription is one show.** A channel, a playlist, or an `@handle`. The show's name is the one you give it, never whatever yt-dlp reports as the uploader, so three playlists from one channel stay three shows.
- **Episodes are numbered by upload date** (`s2026e092401`: the first video uploaded on 24 September 2026). Adding a back catalogue later never renumbers anything, and two videos on one day never share a number.
- **Rules per subscription.** A start date, title filters, minimum and maximum length, Shorts and livestream recordings in or out, quality up to 4K, and keeping only the newest episodes or the last few weeks.
- **SponsorBlock segments are cut exactly**, frame-accurately, while the video is encoded to HEVC, with subtitles and chapters moved to match. Or marked as chapters instead, per subscription. Encoding runs on Intel Quick Sync, AMD or Intel VA-API, NVIDIA NVENC, or the CPU, or can be switched off.
- **A failure is a state with a reason.** "Waiting to retry" passes on its own and says when it will try again. "Needs you" will not, says why, and is on the front page. Nothing is marked done that is not on disk.
- **It watches its own access to YouTube.** It checks every hour whether yt-dlp can still extract a video, whether your cookies are still a live sign-in, and whether the PO token provider is up. It updates yt-dlp daily, checks the download's checksum, and switches only after the new version passes the same check. When YouTube starts refusing, it pauses the whole queue instead of burning through it.
- **It adopts what you already have.** Point it at a Pinchflat or TubeSync library, or anything yt-dlp wrote, and it files those videos into its own layout without downloading them again. You see the whole plan before anything moves.
- **One-off grabs from anywhere.** Share a video from your iPhone or Mac, click the browser extension, or paste a link, and it lands in a `Grabs` folder as a film. Any site yt-dlp can download from, not only YouTube.
- **The files are the library.** Every file carries its YouTube id (or, for another site, `site.id`) in its name and its NFO. Lose the database and nothing on disk is lost.

## Getting started

You need Docker with Compose and a folder for the library that your media server can read.

```sh
git clone <this repository> cylindarr && cd cylindarr
cp .env.example .env          # set PUID, PGID, TZ and a password
mkdir data
# edit compose.yaml: the library volume, and a GPU block if you have one
docker compose up -d --build
```

Open `http://<your server>:8295`, then:

1. **Settings.** Check the library root, add your Plex or Jellyfin details, and look at the access line at the top of the overview. It should say extraction and PO tokens are ok within a minute.
2. **Subscriptions.** Paste a channel URL or `@handle` and press Follow. It starts from 30 days back unless you ask for the whole back catalogue.
3. **Media server.** Add `<library>/Shows` to a TV library and `<library>/Grabs` to a Movies library, with NFO metadata turned on.

[docs/install.md](docs/install.md) covers each step in more detail, including permissions, GPUs, and running behind a reverse proxy.

## Documentation

| | |
|---|---|
| [Installing](docs/install.md) | Compose, the library folder, permissions, GPUs, passwords, reverse proxies, and updates |
| [Configuration](docs/configuration.md) | Every setting, and the environment variables that can fix one in place |
| [Subscriptions](docs/subscriptions.md) | Following, rules, back catalogues, retention, and grabs |
| [Reaching YouTube](docs/youtube-access.md) | The bot check, PO tokens, cookies, proxies, and what Cylindarr does when YouTube says no |
| [Apps and the browser extension](docs/apps.md) | Grabbing from the share sheet, the Mac, and Chromium browsers; pairing; the JSON API |
| [Media servers](docs/media-servers.md) | Setting up Plex, Jellyfin, and Emby libraries, and the refresh after each download |
| [Encoding](docs/encoding.md) | HEVC, SponsorBlock cutting, the encoder choices, and switching encoding off |
| [The library](docs/library.md) | Folders, file names, episode numbers, and NFOs |
| [Adopting a library](docs/adopting.md) | Bringing a Pinchflat, TubeSync, or yt-dlp tree across without downloading again |
| [Troubleshooting](docs/troubleshooting.md) | Reading the journal and what each failure means |
| [How it works](docs/how-it-works.md) | The design, for anyone changing the code |
| [Development](docs/development.md) | Building, testing, and running it from source |

## Status

Version 0.3.0. It runs one household's library every day, on an Intel machine with Quick Sync, beside Plex and Jellyfin. It has not yet met many other setups: the AMD and NVIDIA encoders are tested against their command lines but not yet on the hardware, and Emby has not been tried. I've tried to anticipate the needs other people will have, but it is of course still going to be fairly bespoke. Expect rough edges, and please open an issue when you find one, and make feature or accomodation suggestions and I will listen.

There is no published image yet, so the compose file builds it from this repository.

## YouTube's terms

Downloading from YouTube is against YouTube's terms of service. Every tool in this space says so and leaves the decision to you, and so does Cylindarr.

Cylindarr is for personal archiving: keeping your own copy of the channels and playlists you follow, filed for your own media server. It is not for republishing anyone's videos.

It contains no code that gets around YouTube's protections. The downloading is done by yt-dlp, which Cylindarr runs as a separate program. The proof-of-origin tokens YouTube asks for come from bgutil-ytdlp-pot-provider, a separate project in its own container. Cookies, if you give it any, belong to your own account and are used only by yt-dlp, only for videos that need you signed in. It does not get around DRM and does not download purchased or rented content.

## Contributing

Issues and suggestions are welcome. Pull requests and code are not accepted; [CONTRIBUTING.md](CONTRIBUTING.md) says what helps instead.

## License

[AGPL-3.0](LICENSE). Cylindarr stands on [yt-dlp](https://github.com/yt-dlp/yt-dlp), [FFmpeg](https://ffmpeg.org), [SponsorBlock](https://sponsor.ajay.app), [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider), [Deno](https://deno.com), and [Vapor](https://vapor.codes).
