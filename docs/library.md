# The library

What Cylindarr writes to disk, and why each piece is shaped the way it is. The short version: every file says which YouTube video it is, so the folder is the library and the database is only Cylindarr's notes about it.

## The shape

```
youtube/
  cylindarr-subscriptions.json
  .cylindarr/staging/
  Shows/
    Technology Connections/
      tvshow.nfo
      poster.jpg
      fanart.jpg
      banner.jpg
      Season 2026/
        s2026e092401 - Engines haven't been fully mechanical in decades [0KoeY54M5VA].mp4
        s2026e092401 - Engines haven't been fully mechanical in decades [0KoeY54M5VA].nfo
        s2026e092401 - Engines haven't been fully mechanical in decades [0KoeY54M5VA]-thumb.jpg
        s2026e092401 - Engines haven't been fully mechanical in decades [0KoeY54M5VA].en.srt
  Grabs/
    Me at the zoo (2005) [jNQXAC9IVRw]/
      Me at the zoo (2005) [jNQXAC9IVRw].mp4
      Me at the zoo (2005) [jNQXAC9IVRw].nfo
      poster.jpg
```

## Shows

**One subscription is one show**, and its folder and title are the subscription's name. Cylindarr writes the show title into `tvshow.nfo` and into every episode's NFO, and never takes it from yt-dlp's uploader or playlist title. That is what keeps three playlists from one channel as three shows.

**A season is a year.** A channel with 700 videos is much easier to browse by year, and every tool agrees on what `Season 2019` means.

**Artwork.** A channel's show folder gets `poster.jpg` from the channel's avatar and `fanart.jpg` and `banner.jpg` from its banner, fetched once when the first episode arrives. A playlist's show gets its channel's avatar as the poster and its lead video's still as fanart.

## Episode numbers

The season is the upload year, and the episode is the month, the day, and a two-digit count for that day: the second video uploaded on 18 July 2017 is `s2017e071802`.

- **It is stable.** A number depends only on the video's own upload day and the numbers already taken that day, so adding a back catalogue later never renumbers anything already in the library. A running count (episode 1, 2, 3 in upload order) renumbers a whole year the moment an older video arrives.
- **It never collides.** Numbering by day alone (`s2017e0718`, which Pinchflat does) gives every video uploaded on the same day the same number, and a media server then shows one of them, or shows them as parts of one episode.
- **It sorts** as a number and as text, and you can read the date out of it.
- Days are YouTube's, which are UTC, so an episode's number does not depend on the server's time zone.

## File names

`s<season>e<episode> - <title> [<id>].<ext>`

- **The id in brackets is the identity.** It is how Cylindarr, and anything else that follows yt-dlp's naming, knows which video a file is without a database. Plex and Jellyfin take the displayed title from the NFO, so the bracket never shows in the media server.
- Titles are cleaned for file systems and network shares: `/` and `\` become `-`, `:` becomes ` -`, the characters Windows and SMB refuse (`?`, `*`, `"`, `<`, `>`, `|`) are removed, and the whole name stays under 200 bytes, cut at a word boundary. Everything else stays, including non-Latin text. yt-dlp's habit of swapping in full-width look-alikes (`：`, `？`) is undone rather than copied.
- If YouTube retitles a video after it is placed, the NFO takes the new title the next time the video is downloaded, and the files are renamed with it.

## NFOs

Every episode's NFO carries its title, the show title, season and episode, the air date, the description with its links intact, the runtime, the channel as studio, the thumbnail, and `<uniqueid type="youtube">`. When SponsorBlock segments were cut, the description ends with a note of how many.

`tvshow.nfo` carries the show's title and the channel or playlist id. A grab's NFO is a `<movie>` with its title, year, description, runtime, channel, and id.

## Subtitles

The languages on the settings page (English by default), as `.srt` sidecars named for the episode: `.en.srt`, `.de.srt`, `.pt-BR.srt`. YouTube's automatic captions are used only when a subscription asks for them and a video has no real ones. When SponsorBlock segments are cut, the subtitles are cut to match.

## Grabs

A grab is a film: `Grabs/<Title> (<Year>) [<id>]/`, with the video, its NFO, and the thumbnail as `poster.jpg`.

## What else is there

- **`cylindarr-subscriptions.json`** holds every subscription and its rules, rewritten after each change, so a lost database does not lose what you followed.
- **`.cylindarr/staging/`** is where downloads are assembled. Each video gets its own folder, named for its id, which is removed once the video is placed or has failed. Keeping staging under the library root makes placing a finished download a rename.

## Deleting things

Cylindarr deletes files in three cases only, each of them something you asked for: a retention rule ("keep the newest 10"), **Keep only from a date**, and replacing a video's file with a new download of the same video. Unfollowing a show leaves its files alone.

If you delete an episode yourself, Cylindarr still has it recorded as placed and will not download it again.
