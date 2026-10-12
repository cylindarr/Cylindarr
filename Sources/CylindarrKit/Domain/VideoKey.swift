import Foundation

/// A video's key: its database id, the name of its staging folder and files,
/// and the bracket in its file name. A YouTube video's key is its bare
/// 11-character id, as it always was. A video from any other site is
/// `<extractor>.<id>` in yt-dlp's own terms (`vimeo.76979871`), and the dot,
/// which no YouTube id contains, is what tells the two apart. A grab whose
/// URL has not been resolved yet is `url.<hash>` until it is.
public enum VideoKey {
    public static let unresolvedPrefix = "url."

    public static func isYouTube(_ key: String) -> Bool { Identifier.isVideoID(key) }

    public static func isUnresolved(_ key: String) -> Bool { key.hasPrefix(unresolvedPrefix) }

    /// From yt-dlp's `extractor_key` and `id`. YouTube's extractor gives the
    /// bare id, so a YouTube URL grabbed through another route still meets
    /// the record it already has.
    public static func make(extractor: String, id: String) -> String {
        let site = extractor.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if site == "youtube", Identifier.isVideoID(id) { return id }
        let cleanID = String(id.unicodeScalars.map { Identifier.idCharacters.contains($0) ? Character($0) : "_" })
        return "\(site.isEmpty ? "site" : site).\(cleanID.prefix(80))"
    }

    /// The site and the site's id, for an NFO's `<uniqueid type="...">`.
    public static func parts(_ key: String) -> (site: String, id: String) {
        guard !isYouTube(key), let dot = key.firstIndex(of: ".") else { return ("youtube", key) }
        return (String(key[..<dot]), String(key[key.index(after: dot)...]))
    }

    /// Any key: a YouTube id, or `site.id` with a lower-case site.
    public static func isKey(_ s: String) -> Bool {
        if isYouTube(s) { return true }
        let p = parts(s)
        return !p.site.isEmpty && p.site.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
            && !p.id.isEmpty && Identifier.onlyIDCharacters(p.id)
    }
}
