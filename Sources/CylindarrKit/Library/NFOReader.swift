import Foundation

/// Reads what another tool's NFO says about a video: Pinchflat's and
/// TubeSync's both carry `<uniqueid type="youtube">`, a title, an air date
/// and the description. Used by Adopt when a video has no `.info.json`.
public enum NFOReader {
    public static func facts(_ xml: String) -> Adopter.Facts? {
        guard let id = value(of: #"uniqueid[^>]*type=["']youtube["'][^>]*"#, in: xml) ?? value(of: "id", in: xml),
              Identifier.isVideoID(id), let title = value(of: "title", in: xml) else { return nil }
        guard let aired = (value(of: "aired", in: xml) ?? value(of: "premiered", in: xml)).flatMap(day) else { return nil }
        let runtime = value(of: "runtime", in: xml).flatMap { Int($0) }
        return Adopter.Facts(id: id, title: unescape(title), uploaded: aired,
                             duration: runtime, description: value(of: "plot", in: xml).map(unescape),
                             uploader: value(of: "studio", in: xml).map(unescape))
    }

    static func value(of tag: String, in xml: String) -> String? {
        let name = tag.split(separator: "[").first.map(String.init) ?? tag
        let pattern = "<\(tag)>([\\s\\S]*?)</\(name)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let r = Range(m.range(at: 1), in: xml) else { return nil }
        let v = xml[r].trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// `2017-05-10`, `2017-05-10 00:00:00Z`: the day, at noon UTC.
    static func day(_ s: String) -> Date? {
        let digits = s.prefix(10)
        let parts = digits.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return EpisodeNumbering.calendar.date(from: c)
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
}
