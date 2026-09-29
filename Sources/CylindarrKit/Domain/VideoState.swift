import Foundation

/// Every video Cylindarr has seen is in exactly one of these, and every state
/// that is not final says what happens next. This is the model Pinchflat does
/// not have: it records a download the bot check blocked as `completed` and
/// never looks at it again.
public enum VideoState: Codable, Sendable, Equatable {
    case seen
    case skipped(SkipReason)
    case wanted
    /// Failed for a reason that passes on its own. Tried again at `until`.
    case deferred(DeferCause, until: Date)
    /// Failed for a reason a retry will not fix. Waits for a person.
    case failed(FailCause)
    case placed
    /// Deleted on purpose, by a retention rule or by hand. Never fetched again.
    case retired

    public var isFinal: Bool {
        switch self {
        case .skipped, .placed, .retired: true
        case .seen, .wanted, .deferred, .failed: false
        }
    }

    /// The short word the pages and the database use.
    public var name: String {
        switch self {
        case .seen: "seen"
        case .skipped: "skipped"
        case .wanted: "wanted"
        case .deferred: "deferred"
        case .failed: "failed"
        case .placed: "placed"
        case .retired: "retired"
        }
    }
}

public enum SkipReason: String, Codable, Sendable, CaseIterable {
    case beforeCutoff = "before-cutoff"
    case short
    case liveNow = "live-now"
    case livestream
    case tooShort = "too-short"
    case tooLong = "too-long"
    case titleExcluded = "title-excluded"
    case titleNotIncluded = "title-not-included"
    case membersOnly = "members-only"
    case alreadyPlaced = "already-placed"
    case byHand = "by-hand"
    case pastRetention = "past-retention"

    public var sentence: String {
        switch self {
        case .beforeCutoff: "uploaded before the subscription's cutoff"
        case .short: "a Short"
        case .liveNow: "live now; waits for the recording"
        case .livestream: "a livestream recording, and this subscription leaves those out"
        case .tooShort: "shorter than the subscription's minimum"
        case .tooLong: "longer than the subscription's maximum"
        case .titleExcluded: "the title matches the exclude filter"
        case .titleNotIncluded: "the title does not match the include filter"
        case .membersOnly: "members only"
        case .alreadyPlaced: "already placed in another show"
        case .byHand: "skipped by hand"
        case .pastRetention: "older than the subscription keeps"
        }
    }
}

/// Failures that pass on their own, each with its own backoff.
public enum DeferCause: String, Codable, Sendable, CaseIterable {
    case botCheck = "bot-check"
    case rateLimited = "rate-limited"
    case network
    case premiere
    case liveNow = "live-now"
    case lowDisk = "low-disk"
    case accessPaused = "access-paused"
    /// YouTube refused the stream itself (HTTP 403 on the video data) after
    /// extraction worked. Seen 2026-09-27 with a six-week-old yt-dlp that
    /// the current release did not hit: the usual cause is a stale yt-dlp or
    /// a missing PO token, so it waits for Update rather than retrying hard.
    case streamForbidden = "stream-forbidden"
    case unknown

    /// How long to wait before attempt `attempt + 1`, where `attempt` counts
    /// from 1. The bot check waits longest: retrying into it is what keeps an
    /// address flagged.
    public func backoff(afterAttempt attempt: Int) -> TimeInterval {
        let hour: TimeInterval = 3600
        let steps: [TimeInterval]
        switch self {
        case .botCheck: steps = [1 * hour, 3 * hour, 12 * hour, 24 * hour]
        case .rateLimited: steps = [1 * hour, 2 * hour, 6 * hour]
        case .network: steps = [5 * 60, 15 * 60, 1 * hour, 3 * hour]
        case .premiere, .liveNow: steps = [1 * hour]
        case .lowDisk, .accessPaused: steps = [1 * hour]
        case .streamForbidden: steps = [2 * hour, 6 * hour, 24 * hour]
        case .unknown: steps = [1 * hour, 6 * hour]
        }
        return steps[min(max(attempt, 1), steps.count) - 1]
    }

    /// Whether this cause stops every fetch, not just this video's. A full disk
    /// or a dead access path fails every video the same way.
    public var pausesQueue: Bool {
        switch self {
        case .rateLimited, .lowDisk, .accessPaused: true
        default: false
        }
    }

    /// After this many attempts the video stops deferring and waits for a
    /// person. `nil` means it waits as long as the cause lasts.
    public var attemptLimit: Int? {
        switch self {
        case .unknown: 2
        case .network: 8
        case .botCheck: 12
        case .streamForbidden: 6
        default: nil
        }
    }
}

/// Failures a retry will not fix.
public enum FailCause: String, Codable, Sendable, CaseIterable {
    case removed
    case privateVideo = "private"
    case ageRestricted = "age-restricted"
    case membersOnly = "members-only"
    case geoBlocked = "geo-blocked"
    case formatUnavailable = "format-unavailable"
    case gaveUp = "gave-up"
    case unrecognised

    public var sentence: String {
        switch self {
        case .removed: "removed from YouTube, or its account was terminated"
        case .privateVideo: "private"
        case .ageRestricted: "age-restricted, and the cookies' account cannot see it"
        case .membersOnly: "members only"
        case .geoBlocked: "not available in this country"
        case .formatUnavailable: "no format matched, even the fallback"
        case .gaveUp: "deferred too many times"
        case .unrecognised: "yt-dlp failed in a way Cylindarr does not recognise"
        }
    }
}
