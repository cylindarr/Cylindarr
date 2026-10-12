import Foundation

/// The JSON API's wire types, compiled by the server and by the Apple apps,
/// so the two cannot disagree about a field. Foundation only: this target is
/// built on Linux in the server's image and on iOS and macOS in the apps.
///
/// Every call is under `/api/v1/` and carries the server's key as
/// `X-Api-Key`. Dates are ISO 8601.
public enum CylindarrAPI {
    public static let keyHeader = "X-Api-Key"
    public static let pathPrefix = "/api/v1"

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// `cylindarr://pair?url=<server>&key=<key>`, shown on the settings page
    /// as a link and a QR code, and read by the apps and the browser
    /// extension.
    public static func pairingLink(server: String, key: String) -> String {
        var c = URLComponents()
        c.scheme = "cylindarr"
        c.host = "pair"
        c.queryItems = [URLQueryItem(name: "url", value: server), URLQueryItem(name: "key", value: key)]
        return c.string ?? ""
    }

    public static func parsePairingLink(_ text: String) -> (server: URL, key: String)? {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme == "cylindarr", c.host == "pair",
              let server = c.queryItems?.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)),
              server.scheme == "http" || server.scheme == "https",
              let key = c.queryItems?.first(where: { $0.name == "key" })?.value, !key.isEmpty else { return nil }
        return (server, key)
    }
}

/// `GET /api/v1/status`
public struct ServerStatus: Codable, Sendable, Equatable {
    public var version: String
    /// Fetching is switched on in settings.
    public var fetching: Bool
    /// Why YouTube downloads are held, when they are. Grabs from other sites
    /// go on during a YouTube pause.
    public var paused: Pause?
    /// Grabs waiting to be fetched.
    public var grabsWaiting: Int
    /// The key of the video being fetched now.
    public var current: String?

    public struct Pause: Codable, Sendable, Equatable {
        public var until: Date
        public var reason: String
        public var sentence: String
        public init(until: Date, reason: String, sentence: String) {
            self.until = until
            self.reason = reason
            self.sentence = sentence
        }
    }

    public init(version: String, fetching: Bool, paused: Pause?, grabsWaiting: Int, current: String?) {
        self.version = version
        self.fetching = fetching
        self.paused = paused
        self.grabsWaiting = grabsWaiting
        self.current = current
    }
}

/// One grab, as `GET /api/v1/grabs` lists them.
public struct Grab: Codable, Sendable, Equatable, Identifiable {
    /// A YouTube id, `site.id` for another site, or `url.<hash>` while
    /// the URL is being resolved.
    public var key: String
    /// The host name until the title is known.
    public var title: String
    public var state: State
    /// The cause's short name (`bot-check`, `unsupported`) when deferred or failed.
    public var cause: String?
    /// What the cause means, or the last thing yt-dlp said.
    public var detail: String?
    /// When a deferred grab is tried again.
    public var nextAttempt: Date?
    /// 1 is next, among waiting grabs.
    public var position: Int?
    /// The video's own page: YouTube's, or the other site's.
    public var sourceURL: String
    /// Its row on Cylindarr's pages, relative to the server.
    public var rowPath: String
    public var added: Date

    public var id: String { key }

    public enum State: String, Codable, Sendable, CaseIterable {
        case resolving, wanted, fetching, deferred, failed, placed, skipped, retired
    }

    public init(key: String, title: String, state: State, cause: String? = nil, detail: String? = nil,
                nextAttempt: Date? = nil, position: Int? = nil, sourceURL: String, rowPath: String, added: Date) {
        self.key = key
        self.title = title
        self.state = state
        self.cause = cause
        self.detail = detail
        self.nextAttempt = nextAttempt
        self.position = position
        self.sourceURL = sourceURL
        self.rowPath = rowPath
        self.added = added
    }
}

/// `POST /api/v1/grabs`
public struct GrabRequest: Codable, Sendable, Equatable {
    public var url: String
    public init(url: String) { self.url = url }
}

/// The answer to a grab, whatever happened. `message` is a sentence for the
/// share card or the browser's badge tooltip.
public struct GrabResponse: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable {
        /// Wanted, and in line.
        case queued
        /// Already placed, or already waiting.
        case already
        /// A YouTube channel or playlist: `follow` says what following would do.
        case followable
        /// Not something Cylindarr can grab; `message` says why.
        case refused
    }

    public var outcome: Outcome
    public var message: String
    public var grab: Grab?
    public var follow: FollowOffer?

    public init(outcome: Outcome, message: String, grab: Grab? = nil, follow: FollowOffer? = nil) {
        self.outcome = outcome
        self.message = message
        self.grab = grab
        self.follow = follow
    }
}

public struct FollowOffer: Codable, Sendable, Equatable {
    /// `channel` or `playlist`.
    public var kind: String
    /// What to send back to `POST /api/v1/subscriptions`.
    public var url: String
    public init(kind: String, url: String) {
        self.kind = kind
        self.url = url
    }
}

/// `POST /api/v1/subscriptions`
public struct FollowRequest: Codable, Sendable, Equatable {
    public var url: String
    public var name: String?
    public init(url: String, name: String? = nil) {
        self.url = url
        self.name = name
    }
}

public struct FollowResponse: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var message: String
    /// The subscription's page, relative to the server.
    public var pagePath: String
    public init(id: String, name: String, message: String, pagePath: String) {
        self.id = id
        self.name = name
        self.message = message
        self.pagePath = pagePath
    }
}

/// The body of every 4xx and 5xx, as Vapor writes it.
public struct APIErrorBody: Codable, Sendable, Equatable {
    public var error: Bool
    public var reason: String
    public init(reason: String) {
        error = true
        self.reason = reason
    }
}
