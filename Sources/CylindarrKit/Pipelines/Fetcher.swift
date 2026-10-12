import Foundation

/// How a fetch is run. Everything a release user sets on the settings page
/// that changes the yt-dlp command line.
public struct FetchSettings: Sendable, Equatable {
    public var libraryRoot: String
    public var cookiesPath: String?
    /// `socks5://user:password@host:1080`, when downloads should leave from
    /// another address than the server's own (see docs/youtube-access.md).
    public var proxy: String?
    /// The bgutil PO token provider's HTTP base URL.
    public var potProvider: String?
    public var subtitleLanguages: [String]
    public var minFreeBytes: Int64
    public var encode: EncodeSettings

    public init(libraryRoot: String, cookiesPath: String? = nil, proxy: String? = nil, potProvider: String? = nil,
                subtitleLanguages: [String] = ["en"], minFreeBytes: Int64 = 50 * 1_000_000_000,
                encode: EncodeSettings = EncodeSettings()) {
        self.libraryRoot = libraryRoot
        self.cookiesPath = cookiesPath
        self.proxy = proxy
        self.potProvider = potProvider
        self.subtitleLanguages = subtitleLanguages
        self.minFreeBytes = minFreeBytes
        self.encode = encode
    }

    public var stagingRoot: String { libraryRoot + "/" + NamingScheme.stagingFolder }
    public func staging(for id: String) -> String { stagingRoot + "/" + id }
}

public enum FetchArguments {
    /// The whole yt-dlp command line for one video, into its own staging
    /// folder, every file named for its key alone. Naming is Cylindarr's job,
    /// not an output template's. `sourceURL` is a grab's page on a site other
    /// than YouTube, which gets none of the YouTube-only arguments: no
    /// SponsorBlock, no PO tokens, and not the YouTube account's cookies.
    public static func build(videoID: String, sourceURL: String? = nil, rules: Rules, settings: FetchSettings,
                             withCookies: Bool) -> [String] {
        let youtube = sourceURL == nil
        var a = [
            "--no-warnings", "--newline", "--no-progress", "--no-playlist", "--no-overwrites", "--no-mtime",
            "-f", FormatSelector.formatArgument(for: rules.quality, encodes: settings.encode.encodes),
            "-S", FormatSelector.sortArgument(for: rules.quality),
            "--merge-output-format", "mp4", "--remux-video", "mp4",
            "--write-info-json", "--write-thumbnail", "--convert-thumbnails", "jpg",
            "--embed-chapters", "--embed-metadata",
            "--sleep-requests", "1",
            "-P", settings.staging(for: videoID),
            "-o", "\(videoID).%(ext)s",
        ]
        if youtube, let cutoff = rules.cutoff {
            // The exact cutoff, applied by yt-dlp after extraction and before
            // any download. A listing's dates are approximate.
            let c = EpisodeNumbering.calendar.dateComponents([.year, .month, .day], from: cutoff)
            a += ["--dateafter", String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)]
        }
        // Marked, never removed, by yt-dlp: marking puts the segments in the
        // info.json, and the Finisher cuts them while encoding (see Transcode
        // for why yt-dlp's own cut is not used).
        if youtube, rules.sponsorBlock != .off, !rules.sponsorBlockCategories.isEmpty {
            a += ["--sponsorblock-mark", rules.sponsorBlockCategories.joined(separator: ",")]
        }
        if let proxy = settings.proxy { a += ["--proxy", proxy] }
        if youtube, let pot = settings.potProvider { a += ["--extractor-args", "youtubepot-bgutilhttp:base_url=\(pot)"] }
        if youtube, withCookies, let cookies = settings.cookiesPath { a += ["--cookies", cookies] }
        a.append(sourceURL ?? "https://www.youtube.com/watch?v=\(videoID)")
        return a
    }

    /// The second pass: subtitles only, read from the info.json the first
    /// pass saved, so YouTube is not asked to extract the video again. Kept
    /// out of the first pass because yt-dlp's own cutting of subtitle files
    /// fails (see SubtitleCutter).
    public static func subtitles(videoID: String, rules: Rules, settings: FetchSettings) -> [String] {
        let staging = settings.staging(for: videoID)
        var a = [
            "--no-warnings", "--no-progress", "--skip-download",
            "--load-info-json", staging + "/\(videoID).info.json",
            "--write-subs", "--sub-langs", settings.subtitleLanguages.map { "\($0).*" }.joined(separator: ",") + ",-live_chat",
            "--convert-subs", "srt",
            "-P", staging, "-o", "\(videoID).%(ext)s",
        ]
        if rules.autoCaptions { a.append("--write-auto-subs") }
        if let proxy = settings.proxy { a += ["--proxy", proxy] }
        return a
    }
}

/// Fetch: one attempt at one wanted video. Anonymous first; once more with
/// the cookie jar if the failure is one cookies can fix; then the cause
/// decides whether the video defers (with its own backoff) or fails and waits
/// for a person. A success hands the staging folder to the Finisher.
public struct Fetcher: Sendable {
    public let ytdlp: YtDlp
    public let files: FileOps
    public let store: VideoStore
    public let journal: Journal
    public let clock: Clock
    public let finisher: Finisher

    public init(ytdlp: YtDlp, files: FileOps, store: VideoStore, journal: Journal, clock: Clock, finisher: Finisher) {
        self.ytdlp = ytdlp
        self.files = files
        self.store = store
        self.journal = journal
        self.clock = clock
        self.finisher = finisher
    }

    public enum Outcome: Equatable, Sendable {
        case placed(String)
        case skipped(SkipReason)
        case deferred(DeferCause)
        case failed(FailCause)
    }

    public func fetch(_ record: VideoRecord, subscription sub: Subscription, settings: FetchSettings) async -> Outcome {
        var record = record
        let staging = settings.staging(for: record.id)

        if let free = try? files.freeBytes(at: settings.libraryRoot), free < settings.minFreeBytes {
            return await deferVideo(&record, .lowDisk, detail: "\(free / 1_000_000_000) GB free, below the floor")
        }

        try? files.createDirectory(staging)
        var run = await ytdlp.run(FetchArguments.build(videoID: record.id, sourceURL: record.sourceURL, rules: sub.rules, settings: settings, withCookies: false))
        var usedCookies = false
        // The cookie jar is YouTube's account; another site never gets it.
        let cookiesHelp = settings.cookiesPath != nil && record.sourceURL == nil
        if run.exitCode != 0, case .needsCookies = FailureClassifier.diagnose(stderr: run.stderr), cookiesHelp {
            usedCookies = true
            run = await ytdlp.run(FetchArguments.build(videoID: record.id, sourceURL: record.sourceURL, rules: sub.rules, settings: settings, withCookies: true))
        }
        // The bot check is also something signed-in cookies can get past; one
        // signed-in try per attempt, so the account is used only when needed.
        if run.exitCode != 0, !usedCookies, FailureClassifier.diagnose(stderr: run.stderr) == .deferred(.botCheck),
           cookiesHelp {
            usedCookies = true
            run = await ytdlp.run(FetchArguments.build(videoID: record.id, sourceURL: record.sourceURL, rules: sub.rules, settings: settings, withCookies: true))
        }

        guard run.exitCode == 0 else {
            try? files.remove(staging)
            let tail = FailureClassifier.tail(of: run.stderr, lines: 2)
            switch FailureClassifier.diagnose(stderr: run.stderr) {
            case .deferred(let cause):
                return await deferVideo(&record, cause, detail: tail)
            case .failed(let cause):
                return await failVideo(&record, cause, detail: tail)
            case .needsCookies(let cause):
                let why = settings.cookiesPath == nil ? "no cookies configured" : "the cookies' account cannot see it either"
                return await failVideo(&record, cause, detail: "\(why); \(tail)")
            }
        }

        let said = String(decoding: run.stdout, as: UTF8.self) + run.stderr
        if said.contains("upload date is not in range") {
            try? files.remove(staging)
            record.state = .skipped(.beforeCutoff)
            try? await store.save(record)
            journal.record(Entry(verb: .consider, noun: .video, subject: record.id, outcome: .skipped,
                                 detail: "uploaded before the cutoff, known only once extracted"))
            return .skipped(.beforeCutoff)
        }
        journal.record(Entry(verb: .fetch, noun: .video, subject: record.id, outcome: .ok,
                             detail: usedCookies ? "with cookies" : "anonymous"))
        if !settings.subtitleLanguages.isEmpty {
            let subs = await ytdlp.run(FetchArguments.subtitles(videoID: record.id, rules: sub.rules, settings: settings))
            if subs.exitCode != 0 {
                journal.record(Entry(verb: .fetch, noun: .video, subject: record.id, outcome: .failed,
                                     detail: "subtitles: " + FailureClassifier.tail(of: subs.stderr, lines: 1)))
            }
        }
        return await finisher.finish(record, subscription: sub, settings: settings)
    }

    func deferVideo(_ record: inout VideoRecord, _ cause: DeferCause, detail: String) async -> Outcome {
        record.attempts += 1
        if let limit = cause.attemptLimit, record.attempts >= limit {
            return await failVideo(&record, .gaveUp, detail: "\(cause.rawValue) \(record.attempts) times; \(detail)")
        }
        let until = clock.now.addingTimeInterval(cause.backoff(afterAttempt: record.attempts))
        record.state = .deferred(cause, until: until)
        record.lastCause = detail
        try? await store.save(record)
        journal.record(Entry(verb: .fetch, noun: .video, subject: record.id, outcome: .deferred,
                             detail: "\(cause.rawValue), next try \(Fetcher.timeFormatter.string(from: until)) (attempt \(record.attempts + 1))"))
        return .deferred(cause)
    }

    func failVideo(_ record: inout VideoRecord, _ cause: FailCause, detail: String) async -> Outcome {
        journal.record(Entry(verb: .fetch, noun: .video, subject: record.id, outcome: .failed,
                             detail: "\(cause.sentence)"))
        return await Fetcher.fail(&record, cause, detail: detail, store: store, journal: journal)
    }

    /// A video that fails for good waits for a person, unless it was already
    /// placed and this was a second download: then the file it has stays,
    /// and so does its state.
    static func fail(_ record: inout VideoRecord, _ cause: FailCause, detail: String,
                     store: VideoStore, journal: Journal) async -> Outcome {
        record.lastCause = detail
        if record.path != nil {
            record.state = .placed
            record.attempts = 0
            journal.record(Entry(verb: .place, noun: .episode, subject: record.id, outcome: .skipped,
                                 detail: "downloading again failed; the file already placed is kept"))
        } else {
            record.state = .failed(cause)
        }
        try? await store.save(record)
        return .failed(cause)
    }

    nonisolated(unsafe) static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm"
        return f
    }()
}
