import Foundation

/// Everything that touches the outside world, as protocols. The real
/// implementations live in the app target; the test target has fakes. That is
/// what lets the pipelines below run in the logic suite with no network, no
/// yt-dlp and no disk.

public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

public enum HTTPFailure: Error, Equatable, Sendable {
    case status(Int)
    case transport(String)
}

public protocol FeedClient: Sendable {
    /// The body of a 200, or `HTTPFailure` for anything else.
    func get(_ url: URL) async throws -> Data
}

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: String
    public init(exitCode: Int32, stdout: Data, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// yt-dlp, as a process that takes arguments and returns what it printed.
public protocol YtDlp: Sendable {
    func run(_ arguments: [String]) async -> ProcessResult
}

/// ffmpeg, the same way: arguments in, what it printed out. And ffprobe,
/// for how long a file plays.
public protocol FFmpeg: Sendable {
    func run(_ arguments: [String]) async -> ProcessResult
    /// Seconds, or nil when the file cannot be read.
    func duration(of path: String) async -> Double?
}

/// The filesystem, relative to nothing: every path is absolute.
public protocol FileOps: Sendable {
    func exists(_ path: String) -> Bool
    func contents(of directory: String) throws -> [String]
    func read(_ path: String) throws -> Data
    func write(_ data: Data, to path: String) throws
    func createDirectory(_ path: String) throws
    /// `rename(2)`. Refuses, rather than copying, when the two paths are on
    /// different filesystems; placing a download must be atomic.
    func rename(_ from: String, to: String) throws
    func remove(_ path: String) throws
    func freeBytes(at path: String) throws -> Int64
}

/// Where Cylindarr's own records live. The app implements it over Fluent;
/// the test target over a dictionary.
public protocol VideoStore: Sendable {
    func video(_ id: String) async throws -> VideoRecord?
    func save(_ record: VideoRecord) async throws
    /// Wanted videos, and deferred ones whose time has come: grabs first,
    /// then videos never placed before those already placed and wanted
    /// again, oldest first within each.
    func due(at now: Date, limit: Int) async throws -> [VideoRecord]
    /// Episode numbers already placed in a show.
    func numbers(inShow show: String) async throws -> Set<EpisodeNumber>
    func subscription(_ id: UUID) async throws -> Subscription?
}

/// One video Cylindarr has seen and what it decided.
public struct VideoRecord: Codable, Sendable, Equatable {
    public var id: String
    public var subscriptionID: UUID
    public var title: String
    public var uploaded: Date?
    public var state: VideoState
    public var attempts: Int
    public var number: EpisodeNumber?
    /// Relative to the library root, once placed.
    public var path: String?
    public var firstSeen: Date
    public var lastCause: String?
    /// A listing's "3 weeks ago", when no exact time is known.
    public var approximatelyUploaded: Date?
    /// The page a grab from a site other than YouTube is fetched from. A
    /// YouTube video's URL is built from its id, so it has none.
    public var sourceURL: String?

    public init(id: String, subscriptionID: UUID, title: String, uploaded: Date?, state: VideoState = .seen,
                attempts: Int = 0, number: EpisodeNumber? = nil, path: String? = nil, firstSeen: Date,
                lastCause: String? = nil, approximatelyUploaded: Date? = nil, sourceURL: String? = nil) {
        self.approximatelyUploaded = approximatelyUploaded
        self.sourceURL = sourceURL
        self.id = id
        self.subscriptionID = subscriptionID
        self.title = title
        self.uploaded = uploaded
        self.state = state
        self.attempts = attempts
        self.number = number
        self.path = path
        self.firstSeen = firstSeen
        self.lastCause = lastCause
    }
}

extension EpisodeNumber: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let n = EpisodeNumber.parse(Substring(s)) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not an episode number: \(s)")
        }
        self = n
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
