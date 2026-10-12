# Security

## Reporting a vulnerability

Report it privately through GitHub: the repository's **Security** tab, then **Report a vulnerability**. Please don't open a public issue for it.

Cylindarr is one person's project. Reports are read and fixed as time allows, and there is no bounty.

## Supported versions

Only the latest release gets fixes.

## How Cylindarr expects to be run

On a home network or a VPN, with `CYLINDARR_PASSWORD` set. It is not built to face the internet directly. If you expose it, put it behind a reverse proxy with HTTPS, because the login is HTTP Basic and sends the password with every request. [Passwords and exposure](docs/install.md#passwords-and-exposure) has the details.

Cylindarr holds secrets: your YouTube cookies, your Plex token and Jellyfin key, and its own API key. They are stored unencrypted in the data folder, the cookies in `cookies.txt` and the rest in the SQLite database. Anyone who can read that folder has them, so keep it readable only by the user Cylindarr runs as.

## In scope

- Getting past the password or the API key.
- A page on another site changing Cylindarr through a visitor's browser.
- A video's title, URL, or metadata making Cylindarr write outside the library or run a command.
- Cookies, tokens, or the API key leaking through a page, the journal, the API, or a log.
- The apps or the browser extension mishandling the pairing link or the key.

## Out of scope

- Bugs in yt-dlp, FFmpeg, Deno, or bgutil-ytdlp-pot-provider. Report them to those projects.
- Running without a password on a network other people can reach. The documentation says not to.
- YouTube's terms of service.
