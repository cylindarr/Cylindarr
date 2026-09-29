import Foundation

/// What a pasted URL or id names. A handle or legacy name still has to be
/// resolved to a `UC...` channel id before it can be followed, because the
/// feeds and the database key on the id: handles can change, ids cannot.
public enum YouTubeTarget: Equatable, Sendable {
    case channel(String)
    case handle(String)
    case legacyName(String)
    case playlist(String)
    case video(String)
    /// Any other URL. Only a one-off grab accepts these; subscriptions are
    /// YouTube only.
    case other(URL)
}

public enum Identifier {
    static let youtubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com",
        "www.youtube-nocookie.com",
    ]

    /// Reads what someone pastes: a URL in any of YouTube's shapes, or a bare
    /// channel, playlist or video id.
    public static func parse(_ raw: String) -> YouTubeTarget? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let bare = bareID(text) { return bare }
        if text.hasPrefix("@"), isHandle(String(text.dropFirst())) { return .handle(String(text.dropFirst())) }

        let withScheme = text.contains("://") ? text : "https://" + text
        guard let components = URLComponents(string: withScheme), let host = components.host?.lowercased() else {
            return nil
        }
        let query = Dictionary(
            (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first })
        let parts = components.path.split(separator: "/").map(String.init)

        if host == "youtu.be" {
            if let id = parts.first, isVideoID(id) { return .video(id) }
            return nil
        }
        guard youtubeHosts.contains(host) else {
            guard let url = components.url else { return nil }
            return .other(url)
        }

        if let v = query["v"], isVideoID(v) { return .video(v) }
        if parts.first == "playlist", let list = query["list"], isPlaylistID(list) { return .playlist(list) }
        guard let first = parts.first else { return nil }
        switch first {
        case "shorts", "live", "embed", "v":
            if parts.count > 1, isVideoID(parts[1]) { return .video(parts[1]) }
            return nil
        case "channel":
            if parts.count > 1, isChannelID(parts[1]) { return .channel(parts[1]) }
            return nil
        case "c", "user":
            return parts.count > 1 ? .legacyName(parts[1]) : nil
        default:
            if first.hasPrefix("@") {
                let handle = String(first.dropFirst()).removingPercentEncoding ?? String(first.dropFirst())
                return isHandle(handle) ? .handle(handle) : nil
            }
            if let list = query["list"], isPlaylistID(list) { return .playlist(list) }
            // youtube.com/SomeName is the oldest custom URL form.
            return parts.count == 1 ? .legacyName(first) : nil
        }
    }

    static func bareID(_ text: String) -> YouTubeTarget? {
        if isChannelID(text) { return .channel(text) }
        if isPlaylistID(text), text.count > 11 { return .playlist(text) }
        if isVideoID(text) { return .video(text) }
        return nil
    }

    static let idCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    static func onlyIDCharacters(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { idCharacters.contains($0) }
    }

    public static func isVideoID(_ s: String) -> Bool {
        s.count == 11 && onlyIDCharacters(s)
    }

    public static func isChannelID(_ s: String) -> Bool {
        s.count == 24 && s.hasPrefix("UC") && onlyIDCharacters(s)
    }

    /// PL (user playlists), UU (a channel's uploads), OL (albums), FL, RD
    /// (mixes, which are generated and are refused as subscriptions elsewhere).
    public static func isPlaylistID(_ s: String) -> Bool {
        let prefixes = ["PL", "UU", "OL", "FL", "RD", "LL"]
        return s.count >= 13 && prefixes.contains(where: s.hasPrefix) && onlyIDCharacters(s)
    }

    static func isHandle(_ s: String) -> Bool {
        guard (3...30).contains(s.count) else { return false }
        return s.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_" || $0 == "-"
        }
    }

    /// Finds the channel id in a channel page's HTML, which is how a handle is
    /// resolved without spending a yt-dlp call. The page carries it several
    /// ways; `externalId` is the one present on every channel page checked.
    public static func channelID(inChannelPage html: String) -> String? {
        let patterns = [#""externalId":"(UC[A-Za-z0-9_-]{22})""#, #"<meta itemprop="identifier" content="(UC[A-Za-z0-9_-]{22})">"#,
                        #"youtube\.com/channel/(UC[A-Za-z0-9_-]{22})"#]
        for pattern in patterns {
            if let range = html.range(of: pattern, options: .regularExpression) {
                let match = String(html[range])
                if let idRange = match.range(of: #"UC[A-Za-z0-9_-]{22}"#, options: .regularExpression) {
                    return String(match[idRange])
                }
            }
        }
        return nil
    }
}
