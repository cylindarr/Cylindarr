import Foundation

/// Kodi-format NFO, which Plex's own NFO agent (`tv.plex.agents.nfo.series`,
/// what section 24 uses) and Jellyfin both read. The show title always comes
/// from the subscription; the uploader goes in `studio`, where it informs
/// without deciding which show an episode belongs to.
public enum NFOWriter {
    public struct Show: Sendable, Equatable {
        public var title: String
        public var plot: String?
        public var premiered: Date?
        public var studio: String?
        public var youtubeID: String
        public init(title: String, plot: String? = nil, premiered: Date? = nil, studio: String? = nil, youtubeID: String) {
            self.title = title
            self.plot = plot
            self.premiered = premiered
            self.studio = studio
            self.youtubeID = youtubeID
        }
    }

    public struct Episode: Sendable, Equatable {
        public var title: String
        public var showTitle: String
        public var number: EpisodeNumber
        public var aired: Date
        public var plot: String?
        public var runtimeSeconds: Int?
        public var studio: String?
        public var videoID: String
        public var thumb: String?
        public var sponsorBlockCuts: Int
        public init(title: String, showTitle: String, number: EpisodeNumber, aired: Date, plot: String? = nil,
                    runtimeSeconds: Int? = nil, studio: String? = nil, videoID: String, thumb: String? = nil,
                    sponsorBlockCuts: Int = 0) {
            self.title = title
            self.showTitle = showTitle
            self.number = number
            self.aired = aired
            self.plot = plot
            self.runtimeSeconds = runtimeSeconds
            self.studio = studio
            self.videoID = videoID
            self.thumb = thumb
            self.sponsorBlockCuts = sponsorBlockCuts
        }
    }

    public struct Movie: Sendable, Equatable {
        public var title: String
        public var premiered: Date?
        public var plot: String?
        public var runtimeSeconds: Int?
        public var studio: String?
        public var videoID: String
        public init(title: String, premiered: Date? = nil, plot: String? = nil, runtimeSeconds: Int? = nil,
                    studio: String? = nil, videoID: String) {
            self.title = title
            self.premiered = premiered
            self.plot = plot
            self.runtimeSeconds = runtimeSeconds
            self.studio = studio
            self.videoID = videoID
        }
    }

    static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#

    public static func tvshow(_ s: Show) -> String {
        var lines = [header, "<tvshow>"]
        lines.append(element("title", s.title))
        lines.append(element("showtitle", s.title))
        if let plot = s.plot, !plot.isEmpty { lines.append(element("plot", plot)) }
        if let d = s.premiered { lines.append(element("premiered", day(d))) }
        if let studio = s.studio { lines.append(element("studio", studio)) }
        lines.append(#"  <uniqueid type="youtube" default="true">\#(escape(s.youtubeID))</uniqueid>"#)
        lines.append("</tvshow>")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func episode(_ e: Episode) -> String {
        var lines = [header, "<episodedetails>"]
        lines.append(element("title", e.title))
        lines.append(element("showtitle", e.showTitle))
        lines.append(element("season", String(e.number.season)))
        lines.append(element("episode", String(e.number.episode)))
        lines.append(element("aired", day(e.aired)))
        lines.append(element("premiered", day(e.aired)))
        lines.append(element("plot", plot(e.plot, cuts: e.sponsorBlockCuts)))
        if let r = e.runtimeSeconds { lines.append(element("runtime", String(max(1, (r + 30) / 60)))) }
        if let studio = e.studio { lines.append(element("studio", studio)) }
        lines.append(#"  <uniqueid type="youtube" default="true">\#(escape(e.videoID))</uniqueid>"#)
        if let thumb = e.thumb { lines.append(element("thumb", thumb)) }
        lines.append("</episodedetails>")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func movie(_ m: Movie) -> String {
        var lines = [header, "<movie>"]
        lines.append(element("title", m.title))
        if let d = m.premiered {
            lines.append(element("year", String(EpisodeNumbering.calendar.component(.year, from: d))))
            lines.append(element("premiered", day(d)))
        }
        if let plot = m.plot, !plot.isEmpty { lines.append(element("plot", plot)) }
        if let r = m.runtimeSeconds { lines.append(element("runtime", String(max(1, (r + 30) / 60)))) }
        if let studio = m.studio { lines.append(element("studio", studio)) }
        lines.append(#"  <uniqueid type="youtube" default="true">\#(escape(m.videoID))</uniqueid>"#)
        lines.append("</movie>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func plot(_ plot: String?, cuts: Int) -> String {
        let base = plot ?? ""
        guard cuts > 0 else { return base }
        let note = cuts == 1 ? "1 SponsorBlock segment cut." : "\(cuts) SponsorBlock segments cut."
        return base.isEmpty ? note : base + "\n\n" + note
    }

    static func element(_ name: String, _ value: String) -> String {
        "  <\(name)>\(escape(value))</\(name)>"
    }

    static func day(_ d: Date) -> String {
        let c = EpisodeNumbering.calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// XML 1.0 escaping, and removal of the control characters XML 1.0 does
    /// not allow at all. YouTube descriptions do contain them.
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\t", "\n", "\r": out.unicodeScalars.append(scalar)
            default:
                if scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
