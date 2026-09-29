import Foundation

/// A Netscape-format `cookies.txt`, checked on upload so a file that cannot
/// work is refused with a reason instead of silently ignored, which is what
/// Pinchflat does with a cookie file in the wrong place.
public struct CookieJar: Sendable, Equatable {
    public struct Cookie: Sendable, Equatable {
        public let domain: String
        public let name: String
        public let expires: Date?
    }

    public let cookies: [Cookie]

    /// The cookies that make a signed-in YouTube session. Without these yt-dlp
    /// is anonymous, whatever else the file holds.
    public static let requiredNames: Set<String> = ["SAPISID", "__Secure-3PSID", "LOGIN_INFO"]

    public enum Problem: Equatable, Sendable {
        case notNetscapeFormat
        case noYouTubeCookies
        case missing(Set<String>)
        case expired(String, Date)
    }

    public static func parse(_ text: String) -> CookieJar {
        var cookies: [Cookie] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = String(rawLine)
            // curl writes HttpOnly cookies with this prefix on an otherwise
            // commented-looking line.
            if line.hasPrefix("#HttpOnly_") { line = String(line.dropFirst("#HttpOnly_".count)) }
            if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 7 else { continue }
            let expiry = Double(fields[4]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            cookies.append(Cookie(domain: String(fields[0]), name: String(fields[5]), expires: expiry))
        }
        return CookieJar(cookies: cookies)
    }

    public var youtubeCookies: [Cookie] {
        cookies.filter { Self.isYouTube(domain: $0.domain) }
    }

    static func isYouTube(domain: String) -> Bool {
        domain.hasSuffix("youtube.com") || domain.hasSuffix("google.com")
    }

    /// The uploaded file with every cookie but YouTube's and Google's dropped,
    /// so a whole-browser export does not leave the rest of someone's sessions
    /// on disk. Comments go too; the Netscape header is written back.
    public static func youtubeOnly(_ text: String) -> String {
        var kept = ["# Netscape HTTP Cookie File"]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let bare = line.hasPrefix("#HttpOnly_") ? String(line.dropFirst("#HttpOnly_".count)) : line
            if bare.hasPrefix("#") { continue }
            let fields = bare.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 7, isYouTube(domain: String(fields[0])) else { continue }
            kept.append(line)
        }
        return kept.joined(separator: "\n") + "\n"
    }

    /// Everything wrong with the jar at `now`, most serious first. Empty means
    /// it is worth trying; only a signed-in request proves it works.
    public func problems(at now: Date) -> [Problem] {
        if cookies.isEmpty { return [.notNetscapeFormat] }
        let yt = youtubeCookies
        if yt.isEmpty { return [.noYouTubeCookies] }
        var out: [Problem] = []
        let names = Set(yt.map(\.name))
        let missing = CookieJar.requiredNames.subtracting(names)
        if !missing.isEmpty { out.append(.missing(missing)) }
        for c in yt where CookieJar.requiredNames.contains(c.name) {
            if let e = c.expires, e < now { out.append(.expired(c.name, e)) }
        }
        return out
    }

    /// The soonest a required cookie expires: shown on the settings page. A
    /// session usually dies long before this, by rotation, which only the
    /// hourly signed-in check catches.
    public var earliestRequiredExpiry: Date? {
        youtubeCookies.filter { CookieJar.requiredNames.contains($0.name) }.compactMap(\.expires).min()
    }
}
