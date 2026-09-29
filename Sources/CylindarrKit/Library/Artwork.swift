import Foundation

/// What a show folder's pictures are made from. yt-dlp's listing of a
/// channel's videos tab carries the channel's own images: `avatar_uncropped`
/// and `banner_uncropped` at full size (`=s0`), and banner crops of fixed
/// widths. A playlist's listing carries only small thumbnails of its lead
/// video, whose full-resolution still is at a known address.
public enum Artwork {
    /// `poster.jpg`, `fanart.jpg`, `banner.jpg` from a channel's listing.
    public static func forChannel(_ thumbnails: [Listing.Thumbnail]) -> [String: URL] {
        var out: [String: URL] = [:]
        let byID = Dictionary(thumbnails.compactMap { t in t.id.map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
        let squares = thumbnails.filter { ($0.width ?? 0) > 0 && $0.width == $0.height }
        if let avatar = byID["avatar_uncropped"] ?? squares.max(by: { ($0.width ?? 0) < ($1.width ?? 0) }) {
            out["poster.jpg"] = URL(string: avatar.url)
        }
        let wide = thumbnails.filter { t in
            guard let w = t.width, let h = t.height, h > 0 else { return false }
            return Double(w) / Double(h) > 4
        }
        if let banner = byID["banner_uncropped"] ?? wide.max(by: { ($0.width ?? 0) < ($1.width ?? 0) }) {
            out["fanart.jpg"] = URL(string: banner.url)
        }
        if let crop = wide.max(by: { ($0.width ?? 0) < ($1.width ?? 0) }) {
            out["banner.jpg"] = URL(string: crop.url)
        }
        return out
    }

    /// `fanart.jpg` from a playlist's listing: its lead video's
    /// `maxresdefault`. The poster comes from the playlist's channel.
    public static func forPlaylist(_ thumbnails: [Listing.Thumbnail]) -> [String: URL] {
        guard let url = thumbnails.last?.url, let range = url.range(of: #"/vi/[A-Za-z0-9_-]{11}/"#, options: .regularExpression) else {
            return [:]
        }
        let id = url[range].dropFirst(4).dropLast()
        return ["fanart.jpg": URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")!]
    }
}
