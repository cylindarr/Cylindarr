import Crypto
import Fluent
import Vapor
import CylindarrAPI
import CylindarrKit

/// A one-off, from the page's form, the apps or the browser extension. Filed
/// under Grabs as a film, held by a built-in grab-list subscription that is
/// never polled. Answers at once: a YouTube video is wanted under its id, any
/// other URL under a provisional key while Resolve works out what it is in
/// the background.
struct GrabService {
    let req: Request

    func grab(_ raw: String) async throws -> GrabResponse {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch Identifier.parse(text) {
        case nil:
            return GrabResponse(outcome: .refused, message: "That isn't a link.")
        case .video(let id):
            return try await want(key: id, title: id, sourceURL: nil)
        case .channel(let id):
            return try await followable(kind: .channel, id: id, url: text)
        case .playlist(let id):
            return try await followable(kind: .playlist, id: id, url: text)
        case .handle, .legacyName:
            return try await followable(kind: .channel, id: nil, url: text)
        case .other(let url):
            guard url.scheme == "http" || url.scheme == "https", url.host != nil else {
                return GrabResponse(outcome: .refused, message: "Only web links can be grabbed.")
            }
            let source = Self.normalise(url)
            if let existing = try await VideoModel.query(on: req.db).filter(\.$sourceURL == source).first() {
                return try await want(key: existing.id!, title: existing.title, sourceURL: source)
            }
            let key = VideoKey.unresolvedPrefix + Self.hash(source)
            let response = try await want(key: key, title: url.host ?? source, sourceURL: source)
            let engine = req.application.engine
            Task { await engine.resolve(key) }
            return response
        }
    }

    func followable(kind: SubscriptionKind, id: String?, url: String) async throws -> GrabResponse {
        if let id, let sub = try await SubscriptionModel.query(on: req.db).filter(\.$youtubeID == id).first() {
            return GrabResponse(outcome: .already, message: "Already followed as \(sub.name).")
        }
        let noun = kind == .channel ? "channel" : "playlist"
        return GrabResponse(outcome: .followable, message: "That's a YouTube \(noun). Follow it as a show, from 30 days ago?",
                            follow: FollowOffer(kind: kind.rawValue, url: url))
    }

    func want(key: String, title: String, sourceURL: String?) async throws -> GrabResponse {
        let grabs = try await Self.grabsSubscription(on: req.db)
        let store = FluentVideoStore(db: req.db)
        var record: VideoRecord
        if var existing = try await store.video(key) {
            switch existing.state {
            case .placed:
                return GrabResponse(outcome: .already, message: "Already in the library.",
                                    grab: try await Self.dto(existing, on: req))
            case .wanted, .deferred:
                return GrabResponse(outcome: .already, message: Self.line(try await Self.dto(existing, on: req)),
                                    grab: try await Self.dto(existing, on: req))
            default:
                existing.state = .wanted
                existing.attempts = 0
                try await store.save(existing)
                record = existing
            }
        } else {
            record = VideoRecord(id: key, subscriptionID: grabs.id!, title: title, uploaded: nil, state: .wanted,
                                 firstSeen: Date(), sourceURL: sourceURL)
            try await store.save(record)
        }
        req.application.journal.record(Entry(verb: .want, noun: .grab, subject: key, outcome: .wanted,
                                             detail: sourceURL.map { "grab of \($0)" } ?? "grab"))
        await req.application.engine.wakeFetch()
        let dto = try await Self.dto(record, on: req)
        return GrabResponse(outcome: .queued, message: Self.line(dto), grab: dto)
    }

    /// "Queued, 2nd in line." and what is holding it, for the share card.
    static func line(_ g: Grab) -> String {
        switch g.state {
        case .fetching: return "Downloading now."
        case .resolving: return "Queued; working out what's at that link."
        case .deferred: return "Waiting to retry" + (g.cause.map { " (\($0))" } ?? "") + "."
        default:
            guard let p = g.position else { return "Queued." }
            return p == 1 ? "Queued, next in line." : "Queued, \(ordinal(p)) in line."
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    /// Tracking parameters off, so the same video shared twice is one grab.
    static func normalise(_ url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        let tracking: Set<String> = ["fbclid", "gclid", "igshid", "si", "ref", "ref_src", "feature", "mc_cid", "mc_eid"]
        let kept = (c.queryItems ?? []).filter { !$0.name.hasPrefix("utm_") && !tracking.contains($0.name) }
        c.queryItems = kept.isEmpty ? nil : kept
        c.fragment = nil
        return c.string ?? url.absoluteString
    }

    static func hash(_ s: String) -> String {
        String(SHA256.hash(data: Data(s.utf8)).hex.prefix(16))
    }

    static func grabsSubscription(on db: Database) async throws -> SubscriptionModel {
        if let existing = try await SubscriptionModel.query(on: db).filter(\.$youtubeID == SubscriptionResolver.grabsID).first() {
            return existing
        }
        let grabs = SubscriptionModel(Subscription(kind: .playlist, youtubeID: SubscriptionResolver.grabsID, name: "Grabs",
                                                   enabled: false, isGrabList: true))
        try await grabs.create(on: db)
        return grabs
    }

    /// Every subscription whose videos are films: the built-in Grabs and any
    /// YouTube playlist marked as a grab list.
    static func grabListIDs(on db: Database) async throws -> [UUID] {
        try await SubscriptionModel.query(on: db).filter(\.$isGrabList == true).all().compactMap(\.id)
    }

    /// Recent grabs, newest first.
    static func recent(limit: Int, on req: Request) async throws -> [Grab] {
        let ids = try await grabListIDs(on: req.db)
        guard !ids.isEmpty else { return [] }
        let rows = try await VideoModel.query(on: req.db).filter(\.$subscriptionID ~~ ids)
            .sort(\.$firstSeen, .descending).limit(limit).all()
        let context = try await Context.load(on: req)
        return rows.map { context.dto($0.record) }
    }

    static func dto(_ r: VideoRecord, on req: Request) async throws -> Grab {
        try await Context.load(on: req).dto(r)
    }

    /// What a Grab needs beyond its own row: what is fetching now and where
    /// each waiting grab is in line, read once per answer.
    struct Context {
        let current: String?
        let positions: [String: Int]

        static func load(on req: Request) async throws -> Context {
            let due = try await FluentVideoStore(db: req.db).dueGrabs(at: Date(), limit: 200)
            var positions: [String: Int] = [:]
            for (i, r) in due.enumerated() { positions[r.id] = i + 1 }
            return Context(current: await req.application.engine.current, positions: positions)
        }

        func dto(_ r: VideoRecord) -> Grab {
            var state = Grab.State(rawValue: r.state.name) ?? .wanted
            var cause: String?
            var detail: String?
            var next: Date?
            switch r.state {
            case .deferred(let c, let until): cause = c.rawValue; next = until; detail = r.lastCause
            case .failed(let c): cause = c.rawValue; detail = c.sentence
            case .skipped(let why): cause = why.rawValue; detail = why.sentence
            case .seen: state = .wanted
            default: break
            }
            if state == .wanted, VideoKey.isUnresolved(r.id) { state = .resolving }
            if current == r.id { state = .fetching }
            return Grab(key: r.id, title: r.title, state: state, cause: cause, detail: detail, nextAttempt: next,
                        position: state == .wanted || state == .resolving ? positions[r.id] : nil,
                        sourceURL: Links.source(r), rowPath: Links.video(r.id, in: r.subscriptionID), added: r.firstSeen)
        }
    }
}

extension Engine {
    /// Works out what a grab's URL is, and moves the grab from its
    /// provisional key to its real one. Run at once when the grab is made,
    /// and by the fetch loop for any that a restart or a deferral left
    /// unresolved.
    func resolve(_ key: String) async {
        guard VideoKey.isUnresolved(key), resolving.insert(key).inserted else { return }
        defer { resolving.remove(key) }
        guard var record = try? await store.video(key), let url = record.sourceURL else { return }
        let run = await ytdlp.run(Resolve.arguments(url: url, proxy: settings.proxy.isEmpty ? nil : settings.proxy))
        switch Resolve.decide(run) {
        case .resolved(let real, let title, let uploaded):
            try? await VideoModel.find(key, on: app.db)?.delete(on: app.db)
            if var existing = try? await store.video(real) {
                // The same video, grabbed before by another URL.
                switch existing.state {
                case .placed, .wanted, .deferred: break
                default:
                    existing.state = .wanted
                    existing.attempts = 0
                    try? await store.save(existing)
                }
                journal.record(Entry(verb: .resolve, noun: .grab, subject: real, outcome: .ok,
                                     detail: existing.state == .placed ? "already in the library" : "already known; wanted again"))
                return
            }
            let youtube = VideoKey.isYouTube(real)
            let resolved = VideoRecord(id: real, subscriptionID: record.subscriptionID, title: title, uploaded: uploaded,
                                       state: .wanted, firstSeen: record.firstSeen, sourceURL: youtube ? nil : url)
            try? await store.save(resolved)
            journal.record(Entry(verb: .resolve, noun: .grab, subject: real, outcome: .wanted, detail: title))
        case .failed(let cause, let detail):
            record.state = .failed(cause)
            record.lastCause = detail
            // Refused for what it is: the detail is its title.
            if cause == .notVideo || cause == .notOneVideo, !detail.isEmpty { record.title = detail }
            try? await store.save(record)
            journal.record(Entry(verb: .resolve, noun: .grab, subject: key, outcome: .failed, detail: "\(cause.sentence): \(url)"))
            await notify("Grab failed: \(url) is \(cause.sentence).", page: Links.video(key, in: record.subscriptionID))
        case .deferred(let cause, let detail):
            record.attempts += 1
            if let limit = cause.attemptLimit, record.attempts >= limit {
                record.state = .failed(.gaveUp)
            } else {
                record.state = .deferred(cause, until: Date().addingTimeInterval(cause.backoff(afterAttempt: record.attempts)))
            }
            record.lastCause = detail
            try? await store.save(record)
            journal.record(Entry(verb: .resolve, noun: .grab, subject: key, outcome: .deferred, detail: "\(cause.rawValue): \(detail)"))
        }
    }
}
