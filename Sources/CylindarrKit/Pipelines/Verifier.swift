import Foundation

/// Verify: is the way to YouTube working, before a queue of real videos finds
/// out one by one. Runs yt-dlp against a long-lived public video without
/// downloading, once anonymously and once with the cookie jar if there is
/// one, and asks the PO token provider whether it is up.
public struct Verifier: Sendable {
    public let ytdlp: YtDlp
    public let http: FeedClient
    public let journal: Journal
    public let clock: Clock

    /// "Me at the zoo", the first YouTube video, up since 2005.
    public static let canary = "jNQXAC9IVRw"
    /// yt-dlp's name for the signed-in account's subscriptions feed.
    public static let signedInFeed = ":ytsubs"

    static func signedInCheck(_ run: ProcessResult) -> Check {
        if run.exitCode != 0 {
            return run.stderr.contains("Login details are needed")
                ? .failed("the cookies are not a signed-in session")
                : .failed(FailureClassifier.tail(of: run.stderr, lines: 1))
        }
        if run.stderr.contains("cookies are no longer valid") {
            return .failed("the session was signed out or rotated away")
        }
        return .ok
    }

    public init(ytdlp: YtDlp, http: FeedClient, journal: Journal, clock: Clock) {
        self.ytdlp = ytdlp
        self.http = http
        self.journal = journal
        self.clock = clock
    }

    public enum Check: Equatable, Sendable, Codable {
        case ok
        case off
        case failed(String)

        public var isOK: Bool { self == .ok }
    }

    public struct Report: Equatable, Sendable, Codable {
        public var at: Date
        public var ytdlpVersion: String?
        public var extraction: Check
        public var cause: DeferCause?
        public var cookies: Check
        public var potProvider: Check
        public var egress: String

        /// Fetching may run. Cookies and the PO token provider are helpers;
        /// only anonymous extraction failing stops the queue.
        public var passes: Bool { extraction.isOK }
    }

    public func verify(settings: FetchSettings) async -> Report {
        let version = await ytdlp.run(["--version"])
        let versionText = version.exitCode == 0
            ? String(decoding: version.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : nil

        var route: [String] = []
        if let proxy = settings.proxy { route += ["--proxy", proxy] }
        if let pot = settings.potProvider { route += ["--extractor-args", "youtubepot-bgutilhttp:base_url=\(pot)"] }
        let base = ["--simulate", "--no-warnings", "--no-playlist", "--print", "id"] + route
        let url = "https://www.youtube.com/watch?v=\(Verifier.canary)"

        let anon = await ytdlp.run(base + [url])
        var cause: DeferCause?
        let extraction: Check
        if anon.exitCode == 0 {
            extraction = .ok
        } else {
            if case .deferred(let c) = FailureClassifier.diagnose(stderr: anon.stderr) { cause = c }
            extraction = .failed(FailureClassifier.tail(of: anon.stderr, lines: 1))
        }

        var cookies = Check.off
        if let jar = settings.cookiesPath {
            // A public video plays anonymously when the session is dead, so it
            // proves nothing. The account's subscriptions feed is refused
            // without a live sign-in, and it is a listing, not the player
            // request the bot check watches. Warnings stay on: a session
            // rotated away in a browser is only a warning.
            let signed = await ytdlp.run(["--flat-playlist", "--playlist-items", "1", "--print", "id"] + route
                                         + ["--cookies", jar, Verifier.signedInFeed])
            cookies = Verifier.signedInCheck(signed)
        }

        var pot = Check.off
        if let base = settings.potProvider, let ping = URL(string: base.hasSuffix("/") ? base + "ping" : base + "/ping") {
            do {
                _ = try await http.get(ping)
                pot = .ok
            } catch {
                pot = .failed("\(error)")
            }
        }

        let report = Report(at: clock.now, ytdlpVersion: versionText, extraction: extraction, cause: cause,
                            cookies: cookies, potProvider: pot, egress: settings.proxy == nil ? "direct" : "proxy")
        func word(_ c: Check) -> String {
            switch c { case .ok: "ok"; case .off: "off"; case .failed: "failed" }
        }
        journal.record(Entry(
            verb: .verify, noun: .access, subject: "youtube", outcome: report.passes ? .ok : .failed,
            detail: "yt-dlp \(versionText ?? "missing"), extraction \(word(extraction))\(cause.map { " (\($0.rawValue))" } ?? ""), cookies \(word(cookies)), PO tokens \(word(pot)), egress \(report.egress)"))
        return report
    }
}

/// Update: moving yt-dlp forward on YouTube's schedule, not the image's. The
/// logic half: which release asset is this platform's, and what its checksum
/// must be. The app downloads, checks, verifies and switches.
public enum YtDlpRelease {
    public struct Release: Decodable, Sendable, Equatable {
        public let tagName: String
        public let assets: [Asset]

        public struct Asset: Decodable, Sendable, Equatable {
            public let name: String
            public let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    public static let latestURL = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!

    public static func assetName(os: String, arch: String) -> String {
        switch (os, arch) {
        case ("linux", "aarch64"), ("linux", "arm64"): "yt-dlp_linux_aarch64"
        case ("linux", _): "yt-dlp_linux"
        default: "yt-dlp_macos"
        }
    }

    public struct Plan: Equatable, Sendable {
        public let version: String
        public let binaryURL: String
        public let sumsURL: String
        public let assetName: String
    }

    /// `nil` when `current` is already the latest, or the release lacks this
    /// platform's binary or its checksums.
    public static func plan(_ release: Release, current: String?, asset: String) -> Plan? {
        guard release.tagName != current,
              let binary = release.assets.first(where: { $0.name == asset }),
              let sums = release.assets.first(where: { $0.name == "SHA2-256SUMS" }) else { return nil }
        return Plan(version: release.tagName, binaryURL: binary.browserDownloadURL, sumsURL: sums.browserDownloadURL, assetName: asset)
    }

    /// The expected SHA-256 for `asset` in a `SHA2-256SUMS` file.
    public static func checksum(for asset: String, in sums: String) -> String? {
        for line in sums.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2, parts[1] == asset || parts[1] == "*" + asset { return String(parts[0]).lowercased() }
        }
        return nil
    }
}
