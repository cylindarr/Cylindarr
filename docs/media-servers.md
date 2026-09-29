# Media servers

Cylindarr writes a library any NFO-reading media server understands, and tells Plex and Jellyfin when a new file lands so it shows up in seconds instead of at the next scheduled scan. Neither needs a plugin.

Two libraries per server:

| Folder | Library type | What is in it |
|---|---|---|
| `<library>/Shows` | TV shows | One show per subscription, a season per year |
| `<library>/Grabs` | Movies | One-off grabs, and everything from a grab-list subscription |

In both, the server should read metadata from the local NFO files (and not look the videos up online, where it will find nothing or, worse, the wrong thing). [The library](library.md) describes what is in each NFO.

## Paths

Cylindarr tells each server a path, and it has to be the path _the server_ sees. If Plex or Jellyfin runs in its own container and mounts the library somewhere else, give the mapping on the settings page as `ours=theirs`:

- Cylindarr sees the library at `/data/youtube`, Jellyfin at `/media/youtube`: `/data/youtube=/media/youtube`.
- Both mount it at the same path (the simplest arrangement): leave it blank.

There is one mapping for Plex and one for Jellyfin.

## Plex

1. **Create the libraries.** A TV Shows library on `Shows/` and a Movies library on `Grabs/`. Under Advanced, choose Plex's NFO agent, which reads the local `.nfo` files (its identifiers are `tv.plex.agents.nfo.series` and `tv.plex.agents.nfo.movie`). The posters and thumbnails beside the videos are the artwork.
2. **Find your token.** Plex's support article "Finding an authentication token / X-Plex-Token" shows how: open any item's XML in Plex Web, and the token is at the end of the URL.
3. **Find each library's section id.** With the token, open `http://<plex>:32400/library/sections?X-Plex-Token=<token>`: each `<Directory>` has a `key`, which is the id. In Plex Web, the library's URL also carries it as `source=`.
4. **On Cylindarr's settings page**, set the Plex URL (`http://host.docker.internal:32400` when Plex runs on the same host), the token, and the TV and Grabs section ids.

After each download Cylindarr asks Plex to refresh just that show's folder (or the grab's folder), and the journal records whether Plex answered.

## Jellyfin

1. **Create the libraries.** A Shows library on `Shows/` and a Movies library on `Grabs/`. Jellyfin reads the NFO files and the artwork beside the videos on its own. Under Metadata downloaders and Image fetchers you can switch off the online sources: they have nothing for YouTube videos.
2. **Create an API key**: Dashboard, API Keys, add one named Cylindarr.
3. **On Cylindarr's settings page**, set the Jellyfin URL (`http://host.docker.internal:8096` on the same host) and the API key.

After each download Cylindarr tells Jellyfin the new file's path, and Jellyfin scans just that file.

## Emby

Emby has the same API for this as Jellyfin, so the Jellyfin settings are expected to work with an Emby URL and an Emby API key. This has not been tested yet; if you try it, please report how it went. Emby reads the same NFO files.

## Other servers

Kodi and anything else that reads Kodi-style NFO files can use the library as it is. Cylindarr cannot tell them about new files, so they pick them up at their next scan.
