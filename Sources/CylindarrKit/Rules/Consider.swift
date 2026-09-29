import Foundation

/// What is known about a video when deciding whether to want it. At `poll`
/// time the feed gives an id, a title and an upload time and nothing else;
/// at fetch time yt-dlp's full JSON fills in duration, Shorts and live status.
/// So a video is considered twice, and a rule that needs a fact nobody has
/// yet passes the first time and is applied the second.
public struct Candidate: Sendable, Equatable {
    public var id: String
    public var title: String
    public var uploaded: Date?
    public var duration: Int?
    public var isShort: Bool?
    public var liveStatus: VideoInfo.LiveStatus?
    public var isMembersOnly: Bool
    /// From a flat listing: YouTube's "3 weeks ago", turned into a date.
    public var approximatelyUploaded: Date?

    public init(id: String, title: String, uploaded: Date? = nil, duration: Int? = nil, isShort: Bool? = nil,
                liveStatus: VideoInfo.LiveStatus? = nil, isMembersOnly: Bool = false, approximatelyUploaded: Date? = nil) {
        self.approximatelyUploaded = approximatelyUploaded
        self.id = id
        self.title = title
        self.uploaded = uploaded
        self.duration = duration
        self.isShort = isShort
        self.liveStatus = liveStatus
        self.isMembersOnly = isMembersOnly
    }

    public init(_ entry: FeedEntry) {
        self.init(id: entry.videoID, title: entry.title, uploaded: entry.published)
    }

    public init(_ info: VideoInfo) {
        self.init(
            id: info.id, title: info.title, uploaded: info.uploaded, duration: info.duration.map { Int($0) },
            isShort: info.isShort, liveStatus: info.liveStatus,
            isMembersOnly: info.availability == "subscriber_only")
    }
}

public enum Decision: Equatable, Sendable {
    case want
    case skip(SkipReason)
    /// Not yet: live now, or a premiere that has not aired.
    case wait(DeferCause)
}

public enum Consider {
    public static func decide(_ c: Candidate, rules: Rules, now: Date = Date()) -> Decision {
        if let cutoff = rules.cutoff, let uploaded = c.uploaded, uploaded < cutoff { return .skip(.beforeCutoff) }
        if let cutoff = rules.cutoff, c.uploaded == nil, let approx = c.approximatelyUploaded,
           approx.addingTimeInterval(tolerance(for: approx, now: now)) < cutoff {
            return .skip(.beforeCutoff)
        }
        // Keeping only the last days: an older video would be retired as
        // soon as it was placed, so it is never fetched.
        if case .days(let days) = rules.retention {
            let oldest = now.addingTimeInterval(-TimeInterval(days) * 86400)
            if let uploaded = c.uploaded, uploaded < oldest { return .skip(.pastRetention) }
            if c.uploaded == nil, let approx = c.approximatelyUploaded,
               approx.addingTimeInterval(tolerance(for: approx, now: now)) < oldest {
                return .skip(.pastRetention)
            }
        }
        if c.isMembersOnly { return .skip(.membersOnly) }
        if c.isShort == true, !rules.includeShorts { return .skip(.short) }
        switch c.liveStatus {
        case .isLive: return rules.includeLivestreams ? .wait(.liveNow) : .skip(.livestream)
        case .isUpcoming: return .wait(.premiere)
        case .wasLive, .postLive: if !rules.includeLivestreams { return .skip(.livestream) }
        case .notLive, nil: break
        }
        if let min = rules.minDuration, let d = c.duration, d < min { return .skip(.tooShort) }
        if let max = rules.maxDuration, let d = c.duration, d > max { return .skip(.tooLong) }
        if let exclude = rules.titleExclude, !exclude.isEmpty, matches(c.title, exclude) { return .skip(.titleExcluded) }
        if let include = rules.titleInclude, !include.isEmpty, !matches(c.title, include) {
            return .skip(.titleNotIncluded)
        }
        return .want
    }

    /// How wrong an approximate date can be: "2 days ago" is good to a day,
    /// "1 year ago" to months. A week, or a quarter of the video's age,
    /// whichever is more. Anything inside it is wanted and yt-dlp's
    /// `--dateafter` makes the exact call at fetch time.
    static func tolerance(for approx: Date, now: Date) -> TimeInterval {
        max(7 * 86400, now.timeIntervalSince(approx) / 4)
    }

    /// Filters are case-insensitive regular expressions. One that does not
    /// compile is matched as plain text, so a stray bracket filters what it
    /// looks like it filters rather than nothing.
    static func matches(_ title: String, _ pattern: String) -> Bool {
        if (try? NSRegularExpression(pattern: pattern)) != nil {
            return title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return title.range(of: pattern, options: .caseInsensitive) != nil
    }
}
