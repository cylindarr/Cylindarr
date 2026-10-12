import Foundation

/// Every unit of work in Cylindarr is a verb applied to a noun, and every one
/// of them writes exactly one `Entry`. The entry *is* the log: verbs do not
/// print anything else. A journal that reads as sentences stays readable at
/// a thousand videos a day.
public enum Verb: String, Codable, Sendable, CaseIterable {
    case follow, poll, enumerate, consider, want, skip, fetch
    case defer_ = "defer", clean, encode, place, describe, notify, adopt, repair
    case reconcile, verify, update, retire, purge, configure, resolve
}

public enum Noun: String, Codable, Sendable, CaseIterable {
    case subscription, show, season, video, episode, grab, access, server, remedy, run, system
}

public enum Outcome: String, Codable, Sendable, CaseIterable {
    case ok, wanted, skipped, deferred, failed
}

/// One journal line. `detail` is the human tail that appears on stdout;
/// `data` carries structured extras for the API.
public struct Entry: Codable, Sendable, Equatable {
    public let verb: Verb
    public let noun: Noun
    public let subject: String
    public let outcome: Outcome
    public let detail: String
    public let data: [String: String]
    public let at: Date

    public init(
        verb: Verb,
        noun: Noun,
        subject: String,
        outcome: Outcome,
        detail: String = "",
        data: [String: String] = [:],
        at: Date = Date()
    ) {
        self.verb = verb
        self.noun = noun
        self.subject = subject
        self.outcome = outcome
        self.detail = Entry.redactCookies(in: detail)
        self.data = Entry.redact(data)
        self.at = at
    }

    /// Credentials never reach a journal entry. Enforced here, once, rather
    /// than trusted to every call site that builds a data bag.
    static let redactedKeys: Set<String> = [
        "token", "api_key", "apikey", "password", "pass", "secret",
        "authorization", "x-plex-token", "x-emby-token", "cookies", "cookie",
    ]

    static func redact(_ data: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        out.reserveCapacity(data.count)
        for (key, value) in data {
            out[key] = redactedKeys.contains(key.lowercased()) ? "<redacted>" : Entry.redactCookies(in: value)
        }
        return out
    }

    /// A yt-dlp command line quoted into a detail must not carry the cookie
    /// jar's path or a token in a URL. The path is not secret, but a
    /// `--cookies` argument next to it tells anyone reading the log exactly
    /// where a live Google session sits.
    public static func redactCookies(in text: String) -> String {
        // A password in a URL (`socks5://user:secret@host`), which the proxy
        // setting carries.
        var out = text.replacingOccurrences(
            of: #"([A-Za-z][A-Za-z0-9+.-]*://[^:/@\s]+):[^@\s]+@"#, with: "$1:<redacted>@", options: .regularExpression)
        guard out.contains("--cookies") || out.contains("X-Plex-Token=") else { return out }
        out = out.replacingOccurrences(
            of: #"--cookies(=|\s+)\S+"#, with: "--cookies <redacted>", options: .regularExpression)
        out = out.replacingOccurrences(
            of: #"X-Plex-Token=[^&\s]+"#, with: "X-Plex-Token=<redacted>", options: .regularExpression)
        return out
    }

    /// The stdout form. Fixed columns so `grep` by verb, noun or outcome works
    /// without a parser, which is all a log shipper such as Alloy or Promtail needs.
    public var line: String {
        let time = Entry.timeFormatter.string(from: at)
        let v = verb.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)
        let n = noun.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)
        let s = "\"\(subject)\"".padding(toLength: 36, withPad: " ", startingAt: 0)
        let o = outcome.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
        return "\(time)  \(v) \(n) \(s) \(o) \(detail)"
    }

    nonisolated(unsafe) private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()
}

/// Where entries go. The fake in the test target just collects them, which is
/// how "every verb writes exactly one entry" is asserted.
public protocol Journal: Sendable {
    func record(_ entry: Entry)
}

public final class CollectingJournal: Journal, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Entry] = []

    public init() {}

    public func record(_ entry: Entry) {
        lock.lock(); defer { lock.unlock() }
        storage.append(entry)
    }

    public var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
