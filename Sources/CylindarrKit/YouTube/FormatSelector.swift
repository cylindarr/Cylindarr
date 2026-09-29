import Foundation

/// The `-f` argument for a subscription's quality. Every download is encoded
/// to HEVC before it is placed (see Transcode), so the source is chosen for
/// quality, not for what clients play: YouTube's best stream at the height,
/// which is usually VP9 or AV1 and at a higher bitrate than its H.264. AAC
/// audio first, so a video with nothing cut keeps its audio as it came.
///
/// SDR first. The encode is 8-bit, and an HDR source squeezed into it without
/// tone mapping comes out washed out; an HDR-only video still downloads.
///
/// DASH (`http…`) before HLS: YouTube's "premium" 1080p (616) is HLS only, at
/// over twice the size, fetched fragment by fragment (2.3
/// GB in 22 minutes for a 53-minute video, 2026-09-28), for a difference the
/// HEVC encode mostly throws away.
///
/// With encoding off the file is placed as it came, so the source is chosen
/// for what clients play instead: H.264 and AAC first, which every Plex and
/// Jellyfin client plays directly. YouTube stops offering H.264 above 1080p,
/// so a 2160p subscription still gets VP9 or AV1 there.
public enum FormatSelector {
    public static func formatArgument(for quality: Quality, encodes: Bool = true) -> String {
        let h = "[height<=\(quality.height)]"
        let best = "\(h)[dynamic_range=?SDR][protocol^=http]"
        let general = "bv*\(best)+ba[acodec^=mp4a]/bv*\(best)+ba/bv*\(h)+ba/b\(h)/b"
        return encodes ? general : "bv*\(best)[vcodec^=avc1]+ba[acodec^=mp4a]/" + general
    }

    /// Resolution first; within it, yt-dlp's own order, which prefers the
    /// newer codecs and the higher bitrate.
    public static func sortArgument(for quality: Quality) -> String {
        "res:\(quality.height)"
    }
}
