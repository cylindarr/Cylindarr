import Foundation

/// Retire by rule: which placed episodes a subscription's retention no
/// longer keeps. "The newest 10" keeps the ten latest uploads; "the last 30
/// days" keeps what went up in the last 30 days. Everything else placed is
/// retired: its files are deleted and it is never fetched again.
public enum RetireByRule {
    public static func toRetire(_ records: [VideoRecord], retention: Retention, now: Date) -> [VideoRecord] {
        let placed = records.filter { $0.state == .placed && $0.path != nil }
        switch retention {
        case .keepAll:
            return []
        case .newest(let n):
            let newestFirst = placed.sorted { a, b in
                let da = day(of: a), db = day(of: b)
                return da == db ? (a.number?.episode ?? 0) > (b.number?.episode ?? 0) : da > db
            }
            return Array(newestFirst.dropFirst(max(n, 0)))
        case .days(let n):
            let oldest = now.addingTimeInterval(-TimeInterval(n) * 86400)
            return placed.filter { day(of: $0) < oldest }
        }
    }

    /// When an episode went up: its upload time, else the day its number
    /// carries, else never (so it is the first to go).
    static func day(of r: VideoRecord) -> Date {
        if let uploaded = r.uploaded { return uploaded }
        if let n = r.number {
            var c = DateComponents()
            c.year = n.season; c.month = n.month; c.day = n.day; c.hour = 12
            if let d = EpisodeNumbering.calendar.date(from: c) { return d }
        }
        return .distantPast
    }
}
