import Foundation

/// What a failed yt-dlp run means. Read from stderr, because that is the only
/// place yt-dlp says why. Each cause has its own next step, which is the whole
/// point: a bot check passes, a removed video does not, and a full disk is
/// nobody's video's fault.
public enum Diagnosis: Equatable, Sendable {
    case deferred(DeferCause)
    case failed(FailCause)
    /// Try once more with the cookie jar before deciding.
    case needsCookies(then: FailCause)
}

public enum FailureClassifier {
    /// Rules are checked in order; the first match wins. More specific
    /// messages come before the general ones they contain ("Video
    /// unavailable. This video has been removed" before "unavailable").
    static let rules: [(pattern: String, diagnosis: Diagnosis)] = [
        ("confirm you.re not a bot", .deferred(.botCheck)),
        ("HTTP Error 429", .deferred(.rateLimited)),
        ("Too Many Requests", .deferred(.rateLimited)),
        ("No space left on device", .deferred(.lowDisk)),
        ("unable to download video data: HTTP Error 403", .deferred(.streamForbidden)),
        ("HTTP Error 403: Forbidden", .deferred(.streamForbidden)),
        ("confirm your age", .needsCookies(then: .ageRestricted)),
        ("age-restricted", .needsCookies(then: .ageRestricted)),
        ("Private video", .needsCookies(then: .privateVideo)),
        ("members-only", .needsCookies(then: .membersOnly)),
        ("Join this channel", .needsCookies(then: .membersOnly)),
        ("available to this channel's members", .needsCookies(then: .membersOnly)),
        // Other sites' sign-in walls. yt-dlp's login hint mentions
        // --cookies too, which is why the bot check above comes first.
        ("only available for registered users", .failed(.needsSignIn)),
        ("provide account credentials", .failed(.needsSignIn)),
        ("[Ll]ogin required", .failed(.needsSignIn)),
        ("Unsupported URL", .failed(.unsupported)),
        ("Premieres in", .deferred(.premiere)),
        ("Premiere will begin", .deferred(.premiere)),
        ("live event will begin", .deferred(.premiere)),
        ("This live event has ended", .deferred(.liveNow)),
        ("removed by the uploader", .failed(.removed)),
        ("account associated with this video has been terminated", .failed(.removed)),
        ("copyright claim", .failed(.removed)),
        ("violating YouTube's", .failed(.removed)),
        ("not made this video available in your country", .failed(.geoBlocked)),
        ("not available in your country", .failed(.geoBlocked)),
        ("Requested format is not available", .failed(.formatUnavailable)),
        ("This video is unavailable", .failed(.removed)),
        ("Video unavailable", .failed(.removed)),
        // A page that is not there, on any site. Before "Unable to download
        // webpage", which a 404 also says.
        ("HTTP Error 404", .failed(.removed)),
        ("Temporary failure in name resolution", .deferred(.network)),
        ("timed out", .deferred(.network)),
        ("Connection reset", .deferred(.network)),
        ("Network is unreachable", .deferred(.network)),
        ("Unable to download webpage", .deferred(.network)),
        ("HTTP Error 5", .deferred(.network)),
    ]

    public static func diagnose(stderr: String) -> Diagnosis {
        // yt-dlp prints warnings first ("No title found in player responses")
        // and the reason on the ERROR line. Classify the ERROR lines when there
        // are any, so a warning's wording never decides the cause.
        let errorLines = stderr.split(separator: "\n").filter { $0.hasPrefix("ERROR:") }.joined(separator: "\n")
        let text = errorLines.isEmpty ? stderr : errorLines
        for rule in rules where text.range(of: rule.pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return rule.diagnosis
        }
        return .deferred(.unknown)
    }

    /// The last few lines of stderr, kept on the Grab so a new YouTube change
    /// is readable on the page the day it appears.
    public static func tail(of stderr: String, lines: Int = 6) -> String {
        stderr.split(separator: "\n", omittingEmptySubsequences: true).suffix(lines).joined(separator: "\n")
    }
}
