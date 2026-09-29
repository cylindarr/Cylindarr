import Foundation

/// Season is the upload year. Episode is month, day and a two-digit index for
/// that day: the second video uploaded on 18 July 2017 is `s2017e071802`.
///
/// A number depends only on the video's own day and on the numbers already
/// taken that day, so adding back catalogue later never renumbers anything
/// already in the library, and two videos on one day never share a number.
/// Pinchflat's `e0718` gives three videos uploaded on 18 July the same one.
public struct EpisodeNumber: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let season: Int
    public let episode: Int

    public init(season: Int, episode: Int) {
        self.season = season
        self.episode = episode
    }

    public var dayIndex: Int { episode % 100 }
    public var month: Int { episode / 10_000 }
    public var day: Int { (episode / 100) % 100 }

    /// `s2017e071802`.
    public var description: String {
        "s\(season)e" + String(format: "%06d", episode)
    }

    public static func < (a: EpisodeNumber, b: EpisodeNumber) -> Bool {
        (a.season, a.episode) < (b.season, b.episode)
    }

    /// Reads `s2017e071802` back, and Pinchflat's `s2017e0718` as day index 0,
    /// which is how adoption recognises the old scheme.
    public static func parse(_ s: Substring) -> EpisodeNumber? {
        guard s.first == "s" || s.first == "S" else { return nil }
        let body = s.dropFirst()
        guard let e = body.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return nil }
        guard let season = Int(body[body.startIndex..<e]) else { return nil }
        let digits = body[body.index(after: e)...].prefix(while: \.isNumber)
        guard let n = Int(digits) else { return nil }
        switch digits.count {
        case 6: return EpisodeNumber(season: season, episode: n)
        case 4: return EpisodeNumber(season: season, episode: n * 100)
        default: return nil
        }
    }
}

public enum EpisodeNumbering {
    /// Upload days are YouTube's, which are UTC. Using the server's time zone
    /// instead would move a late-evening upload to the next day in one place
    /// and not another.
    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    public struct Upload: Sendable, Equatable {
        public let id: String
        public let uploaded: Date
        public init(id: String, uploaded: Date) {
            self.id = id
            self.uploaded = uploaded
        }
    }

    /// Numbers `new` videos against the numbers already `taken` in a show.
    /// New videos on the same day are ordered by upload time, then by id, so
    /// the result is the same however they arrive. Each takes the lowest free
    /// index on its day; a video that turns out to be older than one already
    /// placed still takes the next index rather than renumbering it.
    public static func assign(_ new: [Upload], taken: Set<EpisodeNumber>) -> [String: EpisodeNumber] {
        var used = taken
        var out: [String: EpisodeNumber] = [:]
        let ordered = new.sorted { ($0.uploaded, $0.id) < ($1.uploaded, $1.id) }
        for upload in ordered {
            let c = calendar.dateComponents([.year, .month, .day], from: upload.uploaded)
            let base = c.month! * 10_000 + c.day! * 100
            var index = 1
            while used.contains(EpisodeNumber(season: c.year!, episode: base + index)), index < 99 { index += 1 }
            let number = EpisodeNumber(season: c.year!, episode: base + index)
            used.insert(number)
            out[upload.id] = number
        }
        return out
    }
}
