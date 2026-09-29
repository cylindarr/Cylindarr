import Foundation

/// When a subscription's rules change, what is still waiting is decided
/// again. Without this, a cutoff set after the first poll leaves older
/// videos queued until yt-dlp's `--dateafter` turns each away at fetch time,
/// one extraction apiece.
public enum Reconsider {
    /// The records whose state changes, with their new state. Only videos not
    /// yet fetched are touched: wanted, deferred and failed. A video the new
    /// rules would still skip-or-want the same way is left alone, and one now
    /// wanted that was skipped for a rule is not revived here (a person
    /// chooses Want for that).
    public static func changes(_ records: [VideoRecord], rules: Rules, now: Date) -> [VideoRecord] {
        records.compactMap { r in
            switch r.state {
            case .wanted, .deferred, .failed: break
            default: return nil
            }
            let c = Candidate(id: r.id, title: r.title, uploaded: r.uploaded, approximatelyUploaded: r.approximatelyUploaded)
            guard case .skip(let reason) = Consider.decide(c, rules: rules, now: now) else { return nil }
            var out = r
            out.state = .skipped(reason)
            return out
        }
    }
}
