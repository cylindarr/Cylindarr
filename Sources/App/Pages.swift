import Fluent
import Vapor
import CylindarrAPI
import CylindarrKit

/// What each page is given. Plain encodable rows: the templates format
/// nothing, so every decision about wording lives here in Swift.
enum Pages {
    struct VideoRow: Content {
        let id: String
        let title: String
        let show: String
        let showID: String
        let state: String
        let stateLabel: String
        let why: String
        let when: String
        let number: String
        let url: String
        /// Its row on its subscription's page.
        let href: String
    }

    struct EntryRow: Content {
        let at: String
        let verb: String
        let noun: String
        let subject: String
        /// The subject's page in Cylindarr and on YouTube, either blank.
        let subjectHref: String
        let youtube: String
        let outcome: String
        let detail: [Links.Segment]
    }

    struct Banner: Content {
        let level: String
        let text: String
        /// A link after the text, inside Cylindarr, and one to YouTube.
        var link: String = ""
        var href: String = ""
        var youtube: String = ""
    }

    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The words beside a state's colour and glyph, so a state never depends on colour alone.
    static func stateLabel(_ name: String) -> String {
        switch name {
        case "placed": "In the library"
        case "wanted": "Wanted"
        case "deferred": "Waiting to retry"
        case "failed": "Needs you"
        case "skipped": "Skipped"
        case "retired": "Retired"
        default: name.capitalized
        }
    }

    static func row(_ m: VideoModel, names: [UUID: String]) -> VideoRow {
        let r = m.record
        let why: String
        var when = ""
        switch r.state {
        case .skipped(let reason): why = reason.sentence
        case .deferred(let cause, let until): why = cause.rawValue; when = "next try " + short.string(from: until)
        case .failed(let cause): why = cause.sentence + (r.lastCause.map { ": " + $0 } ?? "")
        case .placed: why = r.path.map { ($0 as NSString).lastPathComponent } ?? ""
        default: why = ""
        }
        if when.isEmpty, let u = r.uploaded { when = day.string(from: u) }
        return VideoRow(id: r.id, title: r.title, show: names[r.subscriptionID] ?? "", showID: r.subscriptionID.uuidString,
                        state: r.state.name, stateLabel: stateLabel(r.state.name), why: why, when: when, number: r.number?.description ?? "",
                        url: Links.source(r), href: Links.video(r.id, in: r.subscriptionID))
    }

    static func pauseSentence(_ reason: DeferCause) -> String {
        switch reason {
        case .botCheck: "YouTube's bot check. That is the address, not the videos; retrying into it keeps it flagged."
        case .lowDisk: "The library is below the free-space floor."
        case .rateLimited: "YouTube is rate-limiting this address."
        default: reason.rawValue
        }
    }

    static func names(_ db: Database) async throws -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: try await SubscriptionModel.query(on: db).all().compactMap { m in m.id.map { ($0, m.name) } })
    }

    static func entries(_ db: Database, limit: Int, filter: String? = nil) async throws -> [EntryRow] {
        var q = EntryModel.query(on: db).sort(\.$at, .descending).limit(limit)
        if let f = filter, !f.isEmpty { q = q.filter(\.$outcome == f) }
        let rows = try await q.all()
        let index = try await Links.Index.build(for: rows, on: db)
        return rows.map {
            let links = index.subject($0.subject, noun: $0.noun, verb: $0.verb)
            return EntryRow(at: short.string(from: $0.at), verb: $0.verb, noun: $0.noun, subject: $0.subject,
                            subjectHref: links.href, youtube: links.youtube, outcome: $0.outcome, detail: index.detail($0.detail))
        }
    }

    struct Section: Content {
        let title: String
        let note: String
        let rows: [VideoRow]
    }

    struct Overview: Content {
        let version: String
        let banners: [Banner]
        let counts: [String: Int]
        let needYou: Bool
        let sections: [Section]
        let entries: [EntryRow]
        let paused: Bool
        let current: String?
        let currentHref: String
        let access: [AccessRow]
        let accessChecked: String
    }

    struct AccessRow: Content {
        let part: String
        let state: String
        let detail: String
    }

    static func accessRows(_ r: Verifier.Report?) -> [AccessRow] {
        guard let r else { return [AccessRow(part: "Access", state: "warn", detail: "not checked yet")] }
        func row(_ part: String, _ c: Verifier.Check, off: String) -> AccessRow {
            switch c {
            case .ok: AccessRow(part: part, state: "ok", detail: "working")
            case .off: AccessRow(part: part, state: "off", detail: off)
            case .failed(let why): AccessRow(part: part, state: "bad", detail: why)
            }
        }
        return [
            AccessRow(part: "yt-dlp", state: r.ytdlpVersion == nil ? "bad" : "ok", detail: r.ytdlpVersion ?? "missing"),
            row("YouTube", r.extraction, off: ""),
            row("Cookies", r.cookies, off: "none on file"),
            row("PO tokens", r.potProvider, off: "no provider configured"),
            AccessRow(part: "Egress", state: "ok", detail: r.egress == "proxy" ? "through the proxy" : "direct"),
        ]
    }

    static func overview(_ req: Request) async throws -> Overview {
        let db = req.db
        let n = try await names(db)
        func list(_ state: String, limit: Int) async throws -> [VideoRow] {
            try await VideoModel.query(on: db).filter(\.$state == state).sort(\.$updatedAt, .descending).limit(limit).all().map { row($0, names: n) }
        }
        var counts: [String: Int] = [:]
        for s in ["wanted", "deferred", "failed", "placed", "skipped"] {
            counts[s] = try await VideoModel.query(on: db).filter(\.$state == s).count()
        }
        let status = await req.application.engine.status
        var banners: [Banner] = []
        if let e = req.query[String.self, at: "error"] { banners.append(Banner(level: "bad", text: e)) }
        if let g = req.query[String.self, at: "grabbed"], let video = try await VideoModel.find(g, on: db) {
            let r = video.record
            banners.append(Banner(level: "ok", text: "Wanted \(VideoKey.isUnresolved(g) ? r.title : g); it will be filed under Grabs.",
                                  link: "Its row", href: Links.video(g, in: r.subscriptionID), youtube: Links.source(r)))
        }
        if !status.fetching {
            banners.append(Banner(level: "warn", text: "Fetching is switched off in settings. New videos are noticed and wait.",
                                  link: "Settings", href: "/settings"))
        }
        if !status.gateOpen, let until = status.pausedUntil {
            let why = status.reason == .botCheck
                ? "YouTube asked \(status.consecutiveBotChecks) times in a row to confirm this is not a bot. That is the address, not the videos; retrying into it keeps it flagged."
                : status.reason.map(pauseSentence) ?? ""
            banners.append(Banner(level: "bad", text: "Fetching is paused until \(short.string(from: until)). \(why)",
                                  link: "The access check", href: "/#access"))
        }
        let settings = await AppSettings.load(db)
        if settings.potProvider.isEmpty {
            banners.append(Banner(level: "warn", text: "No PO token provider is configured, so YouTube's bot check comes sooner.",
                                  link: "Settings", href: "/settings#youtube"))
        }
        var sections: [Section] = []
        let failed = try await list("failed", limit: 50)
        if !failed.isEmpty { sections.append(Section(title: "Need you", note: "A retry will not fix these on its own. Each says why.", rows: failed)) }
        let deferred = try await list("deferred", limit: 50)
        if !deferred.isEmpty { sections.append(Section(title: "Waiting to retry", note: "Failed for a reason that usually passes. Each has its own next attempt.", rows: deferred)) }
        let wanted = try await list("wanted", limit: 20)
        if !wanted.isEmpty { sections.append(Section(title: "Next to fetch", note: "", rows: wanted)) }
        sections.append(Section(title: "Recently placed", note: "", rows: try await list("placed", limit: 15)))
        return Overview(
            version: cylindarrVersion, banners: banners, counts: counts, needYou: (counts["failed"] ?? 0) > 0,
            sections: sections, entries: try await entries(db, limit: 25), paused: !status.gateOpen, current: status.current,
            currentHref: try await status.current.asyncMap { id in try await VideoModel.find(id, on: db).map { Links.video(id, in: $0.subscriptionID) } } ?? "",
            access: accessRows(await req.application.engine.lastReport),
            accessChecked: (await req.application.engine.lastReport).map { "checked " + short.string(from: $0.at) } ?? "")
    }

    struct SubscriptionSummary: Content {
        let id: String
        let name: String
        let kind: String
        let youtubeID: String
        let enabled: Bool
        let grabList: Bool
        let placed: Int
        let waiting: Int
        let failed: Int
        let lastPolled: String
        let feedFailures: Int
        let youtubeURL: String
    }

    struct SubscriptionsPage: Content {
        let version: String
        let banners: [Banner]
        let subscriptions: [SubscriptionSummary]
    }

    static func subscriptions(_ req: Request) async throws -> SubscriptionsPage {
        var out: [SubscriptionSummary] = []
        for m in try await SubscriptionModel.query(on: req.db).sort(\.$name).all() where m.youtubeID != SubscriptionResolver.grabsID {
            let id = m.id!
            func count(_ states: [String]) async throws -> Int {
                try await VideoModel.query(on: req.db).filter(\.$subscriptionID == id).filter(\.$state ~~ states).count()
            }
            out.append(SubscriptionSummary(
                id: id.uuidString, name: m.name, kind: m.kind, youtubeID: m.youtubeID, enabled: m.enabled, grabList: m.isGrabList,
                placed: try await count(["placed"]), waiting: try await count(["wanted", "deferred"]), failed: try await count(["failed"]),
                lastPolled: m.lastPolled.map { short.string(from: $0) } ?? "never", feedFailures: m.feedFailures,
                youtubeURL: Links.youtube(m.kind, m.youtubeID)))
        }
        var banners: [Banner] = []
        if let e = req.query[String.self, at: "error"] { banners.append(Banner(level: "bad", text: e)) }
        return SubscriptionsPage(version: cylindarrVersion, banners: banners, subscriptions: out)
    }

    struct SubscriptionPage: Content {
        let version: String
        let id: String
        let name: String
        let kind: String
        let youtubeID: String
        let youtubeURL: String
        let enabled: Bool
        let grabList: Bool
        let rules: RuleForm
        let videos: [VideoRow]
    }

    static func subscription(_ req: Request) async throws -> SubscriptionPage {
        guard let m = try await SubscriptionModel.find(req.parameters.get("id", as: UUID.self), on: req.db) else { throw Abort(.notFound) }
        let s = m.domain
        let rows = try await VideoModel.query(on: req.db).filter(\.$subscriptionID == s.id).sort(\.$firstSeen, .descending).limit(300).all()
        let n = [s.id: s.name]
        return SubscriptionPage(
            version: cylindarrVersion, id: s.id.uuidString, name: s.name, kind: s.kind.rawValue, youtubeID: s.youtubeID,
            youtubeURL: Links.youtube(s.kind.rawValue, s.youtubeID),
            enabled: s.enabled, grabList: s.isGrabList, rules: RuleForm(s), videos: rows.map { row($0, names: n) })
    }

    struct SettingsPage: Content {
        let version: String
        let banners: [Banner]
        let s: AppSettings
        let pinned: [String]
        let hasPinned: Bool
        let cookies: String
        let hasCookies: Bool
        let encoder: String
        let encoderChoices: [Choice]
        let encodes: Bool
        /// Where an app reaches this server, and the link that pairs it.
        let serverURL: String
        let pairingLink: String
        let keyPinned: Bool
    }

    struct Choice: Content {
        let value: String
        let label: String
        let selected: Bool
    }

    static let encoderLabels = [
        "auto": "Automatic: Intel Quick Sync if an Intel GPU is passed in, otherwise the CPU",
        "quicksync": "Intel Quick Sync",
        "vaapi": "VA-API (AMD, or Intel through VA-API)",
        "nvenc": "NVIDIA NVENC",
        "software": "The CPU (libx265, slow)",
        "none": "Do not encode: keep YouTube's file, mark SponsorBlock segments as chapters",
    ]

    static func settings(_ req: Request) async throws -> SettingsPage {
        var s = await AppSettings.load(req.db)
        // The page never shows a password back, including the proxy's.
        s.proxy = Entry.redactCookies(in: s.proxy)
        s.plexToken = ""
        s.jellyfinKey = ""
        let path = await req.application.engine.dataDirectory + "/cookies.txt"
        var cookies = "No cookies. Videos that need a signed-in account fail with that reason."
        let text = try? String(contentsOfFile: path, encoding: .utf8)
        if let text {
            let jar = CookieJar.parse(text)
            let problems = jar.problems(at: Date())
            cookies = problems.isEmpty
                ? "\(jar.youtubeCookies.count) YouTube cookies" + (jar.earliestRequiredExpiry.map { ", the first expiring \(day.string(from: $0))" } ?? "") + ". A session usually dies by rotation long before that."
                : "Cookies on file, but: " + describe(problems) + "."
            if let r = await req.application.engine.lastReport {
                switch r.cookies {
                case .ok: cookies += " The signed-in check passed at \(short.string(from: r.at))."
                case .failed(let why): cookies += " The signed-in check failed at \(short.string(from: r.at)): \(why)"
                case .off: break
                }
            }
        }
        var banners: [Banner] = []
        if let e = req.query[String.self, at: "error"] { banners.append(Banner(level: "bad", text: e)) }
        return SettingsPage(version: cylindarrVersion, banners: banners, s: s, pinned: AppSettings.pinned().sorted(), hasPinned: !AppSettings.pinned().isEmpty, cookies: cookies, hasCookies: text != nil,
                            encoder: Self.describe(s.resolvedEncoder),
                            encoderChoices: AppSettings.encoderChoices.map { Choice(value: $0, label: encoderLabels[$0] ?? $0, selected: $0 == s.encoder) },
                            encodes: s.resolvedEncoder != .none,
                            serverURL: serverURL(req), pairingLink: CylindarrAPI.pairingLink(server: serverURL(req), key: s.apiKey),
                            keyPinned: AppSettings.pinned().contains("CYLINDARR_API_KEY"))
    }

    /// `CYLINDARR_PUBLIC_URL` when set, since a reverse proxy may give the
    /// app another name; otherwise the address this page was asked for.
    static func serverURL(_ req: Request) -> String {
        if let url = Environment.get("CYLINDARR_PUBLIC_URL"), !url.isEmpty { return url.trimmingSuffix("/") }
        let scheme = req.headers.first(name: "X-Forwarded-Proto") ?? "http"
        return "\(scheme)://" + (req.headers.first(name: .host) ?? "localhost:8295")
    }

    static func describe(_ encoder: EncodeSettings.Encoder) -> String {
        switch encoder {
        case .quickSync(let device, _): "HEVC with Intel Quick Sync (\(device))"
        case .vaapi(let device): "HEVC with VA-API (\(device))"
        case .nvenc: "HEVC with NVIDIA NVENC"
        case .software: "HEVC with libx265 on the CPU"
        case .none: "nothing"
        }
    }

    static func describe(_ problems: [CookieJar.Problem]) -> String {
        problems.map {
            switch $0 {
            case .notNetscapeFormat: "that is not a Netscape-format cookies.txt"
            case .noYouTubeCookies: "it holds no YouTube or Google cookies"
            case .missing(let names): "it is missing " + names.sorted().joined(separator: ", ") + ", so it is not a signed-in session"
            case .expired(let name, let when): "\(name) expired \(day.string(from: when))"
            }
        }.joined(separator: "; ")
    }

    struct JournalPage: Content {
        let version: String
        let entries: [EntryRow]
        let filter: String
    }

    static func journal(_ req: Request) async throws -> JournalPage {
        let f = req.query[String.self, at: "outcome"] ?? ""
        return JournalPage(version: cylindarrVersion, entries: try await entries(req.db, limit: 500, filter: f), filter: f)
    }
}

/// The rules as a form. Durations are minutes on the page, seconds inside.
struct RuleForm: Content {
    var name: String
    var enabled: String?
    var cutoff: String
    var titleInclude: String
    var titleExclude: String
    var minMinutes: String
    var maxMinutes: String
    var shorts: String?
    var livestreams: String?
    var autoCaptions: String?
    var quality: String
    var sponsorBlock: String
    var sponsorBlockCategories: String
    var retention: String
    var retentionCount: String

    init(_ s: Subscription) {
        let r = s.rules
        name = s.name
        enabled = s.enabled ? "on" : nil
        cutoff = r.cutoff.map { Pages.day.string(from: $0) } ?? ""
        titleInclude = r.titleInclude ?? ""
        titleExclude = r.titleExclude ?? ""
        minMinutes = r.minDuration.map { String($0 / 60) } ?? ""
        maxMinutes = r.maxDuration.map { String($0 / 60) } ?? ""
        shorts = r.includeShorts ? "on" : nil
        livestreams = r.includeLivestreams ? "on" : nil
        autoCaptions = r.autoCaptions ? "on" : nil
        quality = r.quality.rawValue
        sponsorBlock = r.sponsorBlock.rawValue
        sponsorBlockCategories = r.sponsorBlockCategories.joined(separator: ",")
        switch r.retention {
        case .keepAll: retention = "all"; retentionCount = ""
        case .newest(let n): retention = "newest"; retentionCount = String(n)
        case .days(let n): retention = "days"; retentionCount = String(n)
        }
    }

    static func apply(_ f: RuleForm, to s: inout Subscription) throws {
        let name = f.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { s.name = name }
        s.enabled = f.enabled == "on"
        var r = s.rules
        r.cutoff = f.cutoff.isEmpty ? nil : Pages.day.date(from: f.cutoff)
        r.titleInclude = f.titleInclude.isEmpty ? nil : f.titleInclude
        r.titleExclude = f.titleExclude.isEmpty ? nil : f.titleExclude
        r.minDuration = Int(f.minMinutes).map { $0 * 60 }
        r.maxDuration = Int(f.maxMinutes).map { $0 * 60 }
        r.includeShorts = f.shorts == "on"
        r.includeLivestreams = f.livestreams == "on"
        r.autoCaptions = f.autoCaptions == "on"
        r.quality = Quality(rawValue: f.quality) ?? .hd1080
        r.sponsorBlock = SponsorBlockMode(rawValue: f.sponsorBlock) ?? .cut
        r.sponsorBlockCategories = f.sponsorBlockCategories.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        switch (f.retention, Int(f.retentionCount)) {
        case ("newest", let n?) where n > 0: r.retention = .newest(n)
        case ("days", let n?) where n > 0: r.retention = .days(n)
        default: r.retention = .keepAll
        }
        s.rules = r
    }
}

struct SettingsForm: Content {
    var libraryRoot: String
    var ytdlpPath: String
    var potProvider: String
    var proxy: String
    var subtitleLanguages: String
    var minFreeGB: String
    var pollMinutes: String
    var fetching: String?
    var plexURL: String
    var plexToken: String
    var plexSection: String
    var plexGrabsSection: String
    var plexPathMap: String?
    var jellyfinURL: String
    var jellyfinKey: String
    var jellyfinPathMap: String?
    var ntfyURL: String
    var autoUpdate: String?

    static func apply(_ f: SettingsForm, to s: inout AppSettings) throws {
        s.libraryRoot = f.libraryRoot
        s.ytdlpPath = f.ytdlpPath
        s.potProvider = f.potProvider
        if !f.proxy.contains("<redacted>") { s.proxy = f.proxy }
        s.subtitleLanguages = f.subtitleLanguages
        s.minFreeGB = Int(f.minFreeGB) ?? s.minFreeGB
        s.pollMinutes = max(Int(f.pollMinutes) ?? s.pollMinutes, 5)
        s.fetching = f.fetching == "on"
        s.plexURL = f.plexURL
        // A blank secret field means "unchanged": the page never shows it back.
        if !f.plexToken.isEmpty { s.plexToken = f.plexToken }
        s.plexSection = f.plexSection
        s.plexGrabsSection = f.plexGrabsSection
        s.plexPathMap = f.plexPathMap ?? s.plexPathMap
        s.jellyfinURL = f.jellyfinURL
        if !f.jellyfinKey.isEmpty { s.jellyfinKey = f.jellyfinKey }
        s.jellyfinPathMap = f.jellyfinPathMap ?? s.jellyfinPathMap
        s.ntfyURL = f.ntfyURL
        s.autoUpdate = f.autoUpdate == "on"
    }
}

extension Optional {
    func asyncMap<T>(_ f: (Wrapped) async throws -> T?) async rethrows -> T? {
        guard let w = self else { return nil }
        return try await f(w)
    }
}
