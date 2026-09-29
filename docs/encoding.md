# Encoding

By default every download is encoded to HEVC once, after it is downloaded and before it is placed, and that same pass cuts the SponsorBlock segments. You can switch it off.

## Why encode at all

**The cuts.** yt-dlp can remove SponsorBlock segments itself, by copying the streams and joining the pieces. A copy can only start a piece on a keyframe, and YouTube puts keyframes up to about five seconds apart. The frames between the keyframe and the end of the sponsor segment are kept and squeezed into the moment before the cut, and players that play the squeezed audio drift out of sync from the first cut on. Cutting while encoding drops exactly the frames in each segment and moves every later frame back by the same amount, video and audio alike, so there is nothing to drift. Subtitles and chapters are moved to match.

**The size and the players.** YouTube's best stream at 1080p is usually AV1 or VP9. Not every Plex or Jellyfin client plays those directly, so the server transcodes on every play. HEVC in an MP4, tagged the way Apple's players expect, plays directly on nearly everything current, at about the source's own bitrate.

The source is always YouTube's best standard-dynamic-range stream at the subscription's height. The encode is 8-bit, and an HDR source squeezed into it without tone mapping would come out washed out.

## The encoder

Choose it on the settings page, under Encoding.

| Choice | Uses | Needs |
|---|---|---|
| Automatic (the default) | Intel Quick Sync if an Intel GPU is passed into the container, otherwise the CPU | Nothing |
| Intel Quick Sync | `hevc_qsv` | An Intel GPU with HEVC encode (6th generation Core or later), passed in as `/dev/dri` |
| VA-API | `hevc_vaapi` | An AMD GPU (or Intel) passed in as `/dev/dri`. The image carries Mesa's VA-API drivers on amd64 |
| NVIDIA NVENC | `hevc_nvenc` | An NVIDIA GPU with NVENC, and the NVIDIA Container Toolkit on the host |
| The CPU | `libx265`, preset medium | Nothing, but it is slow: expect a fraction of real time on a small server |
| Do not encode | Nothing | See below |

With Quick Sync, Cylindarr uses the GPU's low-power encoder. Measured on an 11th-generation Intel laptop chip, it was about four times as fast as the default mode (10.7 times real time against 2.8) at the same quality. Intel graphics older than Ice Lake do not have a low-power HEVC encoder; when it refuses, Cylindarr tries the default mode for that video and the journal says so.

Automatic uses only Intel, because that is the path tested on real hardware. AMD and NVIDIA work through the same code and their command lines are tested, but they have not been run on those GPUs yet. If you try one, please report how it went.

### Passing the GPU in

The compose file has both blocks, commented out.

For **Intel or AMD**, pass `/dev/dri` into the container and add the group that owns the render node, so the container's user may open it:

```yaml
    devices:
      - /dev/dri:/dev/dri
    group_add:
      - "993"      # stat -c %g /dev/dri/renderD128 on the host
```

On a machine with more than one GPU, which `renderD` number each gets depends on the order their drivers load, so Cylindarr finds the Intel (or, for VA-API, the AMD) node by its vendor id instead of assuming `renderD128`.

For **NVIDIA**, install the NVIDIA Container Toolkit and reserve the GPU with the `video` capability, which is the one that carries NVENC:

```yaml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu, video, compute, utility]
```

The settings page shows the encoder in use and, for a GPU, which device.

## Quality

One number, 24 by default: the constant QP the GPU encoders get, or libx265's CRF. Lower is better and larger. At 24, a 1080p video comes out at about YouTube's own bitrate, and roughly half the size of YouTube's H.264. Try 22 if you see softness on a large screen, or 27 to save space.

## Not encoding

**Do not encode** places each download as YouTube served it, and prefers YouTube's H.264 and AAC so every client plays it directly. YouTube offers H.264 only up to 1080p; a 2160p subscription still gets VP9 or AV1.

Without an encode there is nowhere to cut, so a subscription set to cut SponsorBlock segments marks them as chapters instead. Most players show chapters, and some can skip them.

This is the right choice for a small machine with no GPU, where libx265 can take longer than the video's own length to encode it.

## Changing your mind

A new encoder or quality applies to downloads from then on. To bring the library in line, press **Download the library again** on the settings page. Every placed video is queued to download and encode again; each keeps its episode number and its current file until the new one is placed, and new uploads go first. For a large library that takes days, at the usual pace.

Before any encode replaces a file, Cylindarr checks that it plays for as long as the source less the cuts. An encode that stopped short is not placed, and a video that already had a file keeps it.
