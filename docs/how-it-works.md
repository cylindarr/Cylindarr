# How it works

For anyone changing the code. It is short on purpose; the code comments carry the detail, and the reasons, next to the lines they are about.

## The one design decision

**The files are the library. The database holds decisions, not a catalogue.**

Every placed video carries its YouTube id in its file name (`[0KoeY54M5VA]`) and in its NFO (`<uniqueid type="youtube">`), and every show folder carries its channel or playlist id in `tvshow.nfo`. So what is on disk can always be read back without the database: which videos exist, which show each belongs to, and where it came from.

The database holds only what the disk cannot say: the subscriptions and their rules, every video Cylindarr has seen and what it decided about it, when it will next try something that failed for a reason that passes, the health of its access to YouTube, and the journal. The test for any change: delete the database, and no video is lost.

A design where the database is the catalogue drifts the first time someone moves a file, deletes an episode in Plex, or restores a backup. Pinchflat's database and its disk disagreeing is one of the reasons this project exists.

## A video's life

Every video is in exactly one state, and every state that is not final says what happens next.

```
seen ─consider─▶ skipped(reason)                    final, unless a person chooses Want
  └─▶ wanted ─fetch─▶ placed ─retire─▶ retired      retired files are gone on purpose
         ▲      │
         │      ├─▶ deferred(cause, until)           passes on its own; back to wanted at `until`
         └──────┘
                └─▶ failed(cause)                    needs a person; on the front page
```

A failure is never "done". A download the bot check blocked is `deferred(bot-check)` with its next attempt time, and a video that cannot be downloaded is `failed` with the reason. Nothing that did not produce a file on disk is ever recorded as placed.

## Verbs and nouns

Every unit of work is a verb applied to a noun, and writes exactly one journal entry: `poll subscription`, `consider video`, `fetch video`, `encode video`, `place episode`, `notify server`, `verify access`, `retire episode`. The entry is the log. Nothing else prints.

## The pipelines

| Pipeline | When | What it does |
|---|---|---|
| Poll | Every subscription, on its interval | The RSS feed; yt-dlp's flat listing of the newest 20 when the feed does not answer. Each unseen video is considered against the rules |
| Enumerate | Following with the back catalogue, or on request | The whole flat listing. Unseen videos are considered; ones skipped for their date are considered again |
| Fetch | One at a time, one to three minutes apart | yt-dlp downloads into a staging folder: anonymous first, once more with cookies if the failure is one cookies fix. The failure's cause decides deferred or failed |
| Finish | After a fetch | Consider again with the full facts, encode with the cuts, number, rename into the show, write the NFOs, cut the subtitles |
| Verify | Hourly, at start, after a cookie upload | Extraction of a public video, the signed-in check, the PO token provider |
| Update | Daily | A new yt-dlp, checked against its checksums and switched in only if Verify passes with it |
| Retire | Hourly and after each placement | The retention rules |
| Adopt | By hand | Another tool's tree into Cylindarr's layout |

The **queue gate** sits in front of Fetch. Three bot checks in a row, a rate limit, or a full disk close it for everyone, because at that point the problem is the address or the disk, and retrying video after video only makes the address look worse.

## The code

Three targets, split so that everything that decides anything can be tested without a network, a disk, or a container.

- **CylindarrKit** holds every decision: the rules, the naming and numbering, the NFOs, failure classification, the cut list and the ffmpeg command line, adoption plans, and the pipelines themselves. It sees the outside world only through the protocols in `Seams/`: a yt-dlp, an ffmpeg, a filesystem, an HTTP client, a store, a clock, a journal.
- **CylindarrSystem** is the real implementation of the seams that are not HTTP: yt-dlp and ffmpeg as child processes, and the filesystem.
- **App** is the Vapor service: the database (Fluent on SQLite), the pages (Leaf), the scheduler (`Engine`, one actor, so "may we fetch now" has one answer), and the HTTP seams.

The tests replay real data: YouTube's feeds, yt-dlp's JSON output, and yt-dlp's actual error text, captured and kept in `Tests/CylindarrKitTests/Fixtures`. A new way for YouTube to fail becomes a new fixture and a new test.
