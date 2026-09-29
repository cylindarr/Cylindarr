import Foundation
@testable import CylindarrKit

final class FixedClock: Clock, @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

final class FakeFeeds: FeedClient, @unchecked Sendable {
    var responses: [URL: Result<Data, HTTPFailure>] = [:]
    func get(_ url: URL) async throws -> Data {
        switch responses[url] ?? .failure(.status(404)) {
        case .success(let d): return d
        case .failure(let e): throw e
        }
    }
}

/// yt-dlp scripted by what its last argument (the URL) is, with an optional
/// side effect standing in for the files a real run writes.
final class FakeYtDlp: YtDlp, @unchecked Sendable {
    struct Step {
        var result: ProcessResult
        var sideEffect: (([String]) -> Void)?
    }
    var steps: [Step] = []
    private(set) var calls: [[String]] = []

    func run(_ arguments: [String]) async -> ProcessResult {
        calls.append(arguments)
        guard !steps.isEmpty else { return ProcessResult(exitCode: 1, stdout: Data(), stderr: "ERROR: no script") }
        let step = steps.removeFirst()
        step.sideEffect?(arguments)
        return step.result
    }

    static func ok(_ stdout: Data = Data()) -> ProcessResult { .init(exitCode: 0, stdout: stdout, stderr: "") }
    static func fail(_ stderr: String) -> ProcessResult { .init(exitCode: 1, stdout: Data(), stderr: stderr) }
}

/// ffmpeg that writes its output (the last argument) into a MemoryFiles, or
/// fails when told to.
final class FakeFFmpeg: FFmpeg, @unchecked Sendable {
    let files: MemoryFiles
    var failure: String?
    /// Fail only a command line containing this argument.
    var failWhen: String?
    /// What ffprobe says of any output.
    var played: Double?
    private(set) var calls: [[String]] = []
    init(files: MemoryFiles, played: Double? = nil) {
        self.files = files
        self.played = played
    }

    func duration(of path: String) async -> Double? { played }

    func run(_ arguments: [String]) async -> ProcessResult {
        calls.append(arguments)
        if let failure, failWhen.map(arguments.contains) ?? true { return ProcessResult(exitCode: 1, stdout: Data(), stderr: failure) }
        files.files[arguments.last!] = Data("hevc".utf8)
        return ProcessResult(exitCode: 0, stdout: Data(), stderr: "")
    }
}

/// A filesystem in a dictionary. Directories exist implicitly.
final class MemoryFiles: FileOps, @unchecked Sendable {
    var files: [String: Data] = [:]
    var free: Int64 = 1_000_000_000_000

    func exists(_ path: String) -> Bool { files[path] != nil || files.keys.contains { $0.hasPrefix(path + "/") } }
    func contents(of directory: String) throws -> [String] {
        let prefix = directory + "/"
        return Set(files.keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count).split(separator: "/")[0]) }).sorted()
    }
    func read(_ path: String) throws -> Data {
        guard let d = files[path] else { throw CocoaError(.fileNoSuchFile) }
        return d
    }
    func write(_ data: Data, to path: String) throws { files[path] = data }
    func createDirectory(_ path: String) throws {}
    func rename(_ from: String, to: String) throws {
        guard let d = files.removeValue(forKey: from) else { throw CocoaError(.fileNoSuchFile) }
        files[to] = d
    }
    func remove(_ path: String) throws {
        files = files.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
    }
    func freeBytes(at path: String) throws -> Int64 { free }
}

actor MemoryStore: VideoStore {
    var videos: [String: VideoRecord] = [:]
    var subscriptions: [UUID: Subscription] = [:]

    func video(_ id: String) async throws -> VideoRecord? { videos[id] }
    func save(_ record: VideoRecord) async throws { videos[record.id] = record }
    func due(at now: Date, limit: Int) async throws -> [VideoRecord] {
        videos.values.filter {
            switch $0.state {
            case .wanted: true
            case .deferred(_, let until): until <= now
            default: false
            }
        }.sorted { ($0.path == nil ? 0 : 1, $0.firstSeen) < ($1.path == nil ? 0 : 1, $1.firstSeen) }.prefix(limit).map { $0 }
    }
    func numbers(inShow show: String) async throws -> Set<EpisodeNumber> {
        let ids = Set(subscriptions.values.filter { $0.name == show }.map(\.id))
        return Set(videos.values.filter { ids.contains($0.subscriptionID) }.compactMap(\.number))
    }
    func subscription(_ id: UUID) async throws -> Subscription? { subscriptions[id] }
    func add(_ s: Subscription) { subscriptions[s.id] = s }
    func all() -> [String: VideoRecord] { videos }
}
