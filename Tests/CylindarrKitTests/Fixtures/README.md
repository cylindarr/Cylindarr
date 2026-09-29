# Fixtures

The feeds, yt-dlp output and error text are real, captured 2026-09-27.

- `feeds/`: YouTube's Atom feeds, fetched with curl. `not-found.html` is the 404 page the playlist feeds return on roughly half of requests.
- `ytdlp/`: yt-dlp `-J` output. The flat listings came from yt-dlp 2026.08.19; the video from yt-dlp 2026.07.04. The video file is trimmed (automatic captions, heatmap, thumbnails and all but three formats removed; stream URLs replaced with placeholders) to keep it small.
- `errors/`: `bot-check.txt`, `age-gate.txt`, `unavailable.txt` and `stream-forbidden.txt` are real stderr. `transcribed.txt` holds messages that cannot be produced on demand, written in YouTube's and yt-dlp's wording, one `cause<TAB>line` per row. Replace a transcribed line with a captured one whenever it is seen for real.
- `trees/`: file listings in the shape Pinchflat and TubeSync write, with the quirks of real ones (every sidecar kind, full-width look-alike characters, a show's own poster and NFO, what an interrupted download leaves). The shows and videos are invented; `make-trees.py` writes them.
