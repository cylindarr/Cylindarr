# Adopting a library

If you already have YouTube videos on disk from Pinchflat, TubeSync, ytdl-sub, or anything else built on yt-dlp, Cylindarr can file them into its own layout without downloading them again. Each video is identified by its YouTube id, from its `.info.json`, its NFO, or its file name. You see the whole plan before anything moves.

## Before you start

1. **Stop the other tool**, so two programs never write the same tree at once.
2. **Switch off "Fetch wanted videos"** on Cylindarr's settings page. Following a subscription polls it at once, and without this Cylindarr would start downloading recent videos you already have.
3. **Mount the old tree** into Cylindarr's container. Mounting it inside the library's volume, or under the same host folder, lets adoption rename files instead of copying them:

   ```yaml
       volumes:
         - /path/to/media/youtube:/data/youtube
         - /path/to/media/pinchflat:/import/pinchflat
   ```

   Across two mounts each file is copied, its size checked, and only then is the original removed. That is safe but slower, and needs the space for both copies of the largest file.
4. **Follow the subscriptions** the old tree came from, with the cutoffs you want. Adoption files each folder into the show of a subscription, so the subscriptions come first. A folder with the same name as a subscription is matched to it automatically.

## Scan, plan, run

On the **Adopt** page, enter the old tree's path as the container sees it (`/import/pinchflat`) and press Scan. Each folder that holds videos is listed with how many it has and how many could be identified. Choose where each goes:

- **Show:** a subscription. Its videos become episodes of that show, numbered by upload day.
- **Grabs (films):** each video becomes a film under `Grabs`. A video here with no id anywhere is still filed, by its file name.
- **Leave alone:** nothing in the folder is touched.

**Show the plan** lists what will happen: how many videos go where, which could not be placed and why, leftovers from interrupted downloads, and the first operations in full. Nothing has moved yet. **Run the adoption** does it, one video at a time, with progress on the Adopt page and every step in the journal.

For each video, adoption:

- moves the media and its subtitles, renamed into Cylindarr's scheme and numbered,
- moves the thumbnail,
- writes a new NFO, and removes the old NFO and `.info.json`,
- records the video as placed, so it is never downloaded again.

Each adopted show gets a `tvshow.nfo` and artwork if it has none.

## What is not adopted

- **Videos with no id** in a folder mapped to a show. The plan lists them as unidentified; they stay where they are.
- **Videos already in the library.** Listed as duplicates and left where they are, so you can compare and delete by hand.
- **Leftovers from interrupted downloads** (`.part`, `.ytdl`, `.temp` files). Listed, never moved; safe to delete by hand.
- **A folder mapped to nothing.** Listed; untouched.

## Afterwards

1. Switch **Fetch wanted videos** back on.
2. Point your media server at the new `Shows/` and `Grabs/` folders ([Media servers](media-servers.md)), and remove the old library from it.
3. When you are happy, delete what is left of the old tree.
