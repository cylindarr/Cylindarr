# Subscriptions

A subscription is a YouTube channel or playlist, and each one becomes one show in your media server.

## Following

On the Subscriptions page, paste any of these and press Follow:

- a channel URL: `https://www.youtube.com/@TechnologyConnections`, `https://www.youtube.com/channel/UC...`, or an old `/c/` or `/user/` URL
- a handle on its own: `@TechnologyConnections`
- a playlist URL, or a playlist id (`PL...`)
- a channel id (`UC...`)

The show's name defaults to YouTube's title for the channel or playlist. Give your own in the second box if you want something else; you can change it later on the subscription's page. Cylindarr never renames a show from what yt-dlp reports, so a playlist from a channel you also follow stays its own show.

**Channel or playlist?** A channel subscription notices everything the channel uploads, and its rules decide what is kept (Shorts are out and livestream recordings in, by default). A back-catalogue listing covers the channel's Videos tab, so older Shorts and streams that only appear on the Shorts and Live tabs are not listed. A playlist follows exactly that playlist. If a creator publishes several series, a playlist per series gives you one show per series.

**Grab list.** Tick it and every video the subscription finds is filed under `Grabs` as a film instead of as an episode, and the rules below do not apply: everything in it is wanted. It suits a playlist you add one-off videos to, such as a public playlist you save videos to for later.

## Where it starts

A new subscription starts from 30 days ago: it wants what went up in the last month, and skips anything older with the reason "before the cutoff". So the first night does not fetch a 700-video back catalogue from one address.

Tick **Whole back catalogue** to start with no cutoff. Cylindarr then lists the whole channel or playlist in the background (a minute or two for a big channel) and queues everything the rules want. The queue downloads one video at a time with a pause between, so a large back catalogue takes days. That pace is deliberate: YouTube's bot check is triggered by volume from one address.

For an existing subscription, clear or move the cutoff on its page, save, and press **List the whole channel**. That finds everything older the rules now want, including videos skipped earlier for their date.

## Rules

Each subscription's page has its rules. Changing them decides again about every video still waiting; a video already downloaded is not deleted by a rule change, except by the retention rule.

| Rule | What it does |
|---|---|
| Show name | The name in the media server, and the folder name |
| Enabled | Off stops polling. What is already queued still downloads |
| Cutoff | Only videos uploaded on or after this date |
| Title must match, must not match | Regular expressions, case-insensitive. A pattern that is not valid regex is matched as plain text |
| At least, at most | Length limits in minutes |
| Include Shorts | Off by default |
| Include livestream recordings | On by default. A stream still live waits until it has finished and its recording is ready |
| Automatic captions | Uses YouTube's generated captions when a video has no real ones |
| Quality | Up to 1080p (the default), up to 2160p, or up to 720p |
| SponsorBlock | Cut the chosen categories, mark them as chapters, or ignore SponsorBlock. The categories are SponsorBlock's names, comma-separated: `sponsor,selfpromo,interaction` by default, and also `intro`, `outro`, `preview`, `filler`, and `music_offtopic` |
| Keep | Everything, the newest N episodes, or the last N days. See below |

Some facts are known only once a video is downloaded (a feed does not say whether a video is a Short, or how long it is), so a video can be wanted when first seen and skipped once fetched. The journal says which rule skipped it.

Members-only videos are always skipped.

## Keeping only the newest

For news and other channels where only the latest matters, set **Keep** to the newest N episodes or the last N days. After each download, and every hour, Cylindarr deletes the episodes the rule no longer keeps (the video and all its sidecars) and records each as retired, so it is never downloaded again. With "the last N days", a video older than that is not downloaded in the first place.

**Keep only from a date**, at the bottom of the subscription's page, is the one-off version: it deletes every episode uploaded before a date and sets the cutoff to it.

## One video at a time

Waiting and failed videos show on the overview and on their subscription's page, each with the reason. **Retry now** puts one back in the queue at once; **Skip** gives up on it; **Want** reverses a rule's skip for that one video.

## Grabs

Paste a single video's URL into the box on the overview and press Grab. It is downloaded next and filed as a film under `Grabs/Title (Year) [id]/`. Grabs take YouTube videos only for now.

## Unfollowing

**Unfollow** forgets the subscription and every video still waiting. Episodes already in the library stay on disk: deleting a show is your call, in your file manager or media server.

## The subscriptions file

After every change Cylindarr writes all subscriptions and their rules to `cylindarr-subscriptions.json` at the library root. If the database is lost, that file is the record of what you followed; following them again is by hand for now.
