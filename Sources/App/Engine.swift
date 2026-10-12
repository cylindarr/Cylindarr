import Fluent
import Vapor
import CylindarrKit
import CylindarrSystem

/// The scheduler and everything it needs: poll every subscription on its
/// interval, fetch one wanted video at a time with a pause between, and keep
/// the queue gate. One actor, so "is fetching allowed" has one answer.
actor Engine {
    let app: Application
    let journal: Journal
    let dataDirectory: String
    private(set) var gate = QueueGate()
    private(set) var settings: AppSettings
    private(set) var current: String?
    var lastReport: Verifier.Report?
    var cookieAlerts = CookieAlerts()
    private var loops: [Task<Void, Never>] = []
    private var pollNow = false
    /// Subscriptions being polled right now. A follow polls at once, and the
    /// scheduler may reach the same one in the same second; two polls would
    /// both record the same new videos.
    private var polling: Set<UUID> = []
    /// Grabs whose URL Resolve is working on now.
    var resolving: Set<String> = []
    /// A grab arrived while the fetch loop was idle.
    private var fetchWake = false

    init(app: Application, journal: Journal, dataDirectory: String, settings: AppSettings) {
        self.app = app
        self.journal = journal
        self.dataDirectory = dataDirectory
        self.settings = settings
    }

    var store: FluentVideoStore { FluentVideoStore(db: app.db) }
    var clock: Clock { SystemClock() }
    var ytdlp: YtDlp {
        var env = ["HOME": dataDirectory]
        if let path = Environment.get("PATH") { env["PATH"] = path }
        return ProcessYtDlp(executable: settings.ytdlpPath, environment: env)
    }

    func start() {
        loops.append(Task { await self.pollLoop() })
        loops.append(Task { await self.fetchLoop() })
        loops.append(Task { await self.maintenanceLoop() })
    }

    /// Verify and retire by rule at start and hourly; update yt-dlp at start
    /// and daily.
    private func maintenanceLoop() async {
        try? await Task.sleep(for: .seconds(10))
        var lastUpdate = Date.distantPast
        while !Task.isCancelled {
            _ = await verifyNow()
            await retireByRule()
            if Date().timeIntervalSince(lastUpdate) > 86_400 {
                lastUpdate = Date()
                await updateYtDlp()
            }
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    func pauseGate(_ cause: DeferCause, for interval: TimeInterval) {
        gate.pause(cause, for: interval, at: Date())
    }

    func resumeGate() {
        gate.resume()
        journal.record(Entry(verb: .configure, noun: .system, subject: "queue", outcome: .ok, detail: "resumed: access check passed"))
    }

    func stop() {
        loops.forEach { $0.cancel() }
    }

    func reload() async {
        settings = await AppSettings.load(app.db)
    }

    func resume() {
        gate.resume()
        journal.record(Entry(verb: .configure, noun: .system, subject: "queue", outcome: .ok, detail: "resumed by hand"))
    }

    func requestPoll() { pollNow = true }

    struct Status: Sendable {
        let gateOpen: Bool
        let pausedUntil: Date?
        let reason: DeferCause?
        let consecutiveBotChecks: Int
        let fetching: Bool
        let current: String?
    }

    var status: Status {
        Status(gateOpen: gate.isOpen(at: Date()), pausedUntil: gate.pausedUntil, reason: gate.reason,
               consecutiveBotChecks: gate.consecutiveBotChecks, fetching: settings.fetching, current: current)
    }

    // MARK: Poll

    private func pollLoop() async {
        try? await Task.sleep(for: .seconds(5))
        while !Task.isCancelled {
            await pollDue()
            for _ in 0..<60 where !pollNow && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
            }
            pollNow = false
        }
    }

    /// Every enabled subscription whose interval has passed, one at a time,
    /// with a few seconds between so a dozen feeds are not asked at once.
    func pollDue(force: Bool = false) async {
        guard let subs = try? await SubscriptionModel.query(on: app.db).filter(\.$enabled == true).all() else { return }
        let interval = TimeInterval(max(settings.pollMinutes, 5) * 60)
        for model in subs where !Task.isCancelled {
            if !force, !pollNow, let last = model.lastPolled, Date().timeIntervalSince(last) < interval { continue }
            await poll(model)
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func poll(_ model: SubscriptionModel) async {
        guard let id = model.id, !polling.contains(id) else { return }
        polling.insert(id)
        defer { polling.remove(id) }
        let poller = Poller(feeds: VaporFeedClient(client: app.client), ytdlp: ytdlp, store: store, journal: journal, clock: clock)
        let result = await poller.poll(model.domain, feedFailures: model.feedFailures)
        model.lastPolled = Date()
        model.feedFailures = result.feedFailed ? model.feedFailures + 1 : 0
        if result.source == .listing { model.feedFailures = 0 }
        try? await model.update(on: app.db)
    }

    /// The whole channel or playlist, for a back catalogue. Shares the poll's
    /// guard, so a poll and an enumeration of one subscription never overlap.
    func enumerate(_ model: SubscriptionModel) async {
        guard let id = model.id, !polling.contains(id) else { return }
        polling.insert(id)
        defer { polling.remove(id) }
        let poller = Poller(feeds: VaporFeedClient(client: app.client), ytdlp: ytdlp, store: store, journal: journal, clock: clock)
        _ = await poller.enumerate(model.domain)
    }

    // MARK: Fetch

    private func fetchLoop() async {
        try? await Task.sleep(for: .seconds(20))
        while !Task.isCancelled {
            let fetched = await fetchNext()
            if fetched {
                // The pause between downloads stays whatever arrives: a burst
                // of downloads from one address is what the bot check watches.
                let pause = Int.random(in: max(settings.pauseSecondsMin, 0)...max(settings.pauseSecondsMax, settings.pauseSecondsMin))
                try? await Task.sleep(for: .seconds(pause))
            } else {
                // Idle: a grab wakes it, so a grab starts within a second.
                for _ in 0..<60 where !fetchWake && !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            fetchWake = false
        }
    }

    func wakeFetch() { fetchWake = true }

    /// One video, if one is due and the gate lets it through. Returns
    /// whether it ran. Grabs come first (see FluentVideoStore.due). The gate
    /// is YouTube's view of this address, so while it is closed a grab from
    /// another site still runs; a full disk stops everything.
    func fetchNext() async -> Bool {
        guard settings.fetching else { return false }
        var youtubeOpen = gate.isOpen(at: Date())
        if youtubeOpen, gate.pausedUntil != nil {
            // The pause has run out. Check before trying a real video again.
            let report = await verifyNow()
            if report.passes { gate.resume() } else { youtubeOpen = false }
        }
        if !youtubeOpen, gate.reason == .lowDisk { return false }
        var picked: VideoRecord?
        // A grab not yet resolved is resolved first; a few rounds at most.
        for _ in 0..<5 {
            guard let due = try? await store.due(at: Date(), limit: youtubeOpen ? 5 : 50),
                  let next = due.first(where: { !resolving.contains($0.id) && (youtubeOpen || !VideoKey.isYouTube($0.id)) })
            else { return false }
            guard VideoKey.isUnresolved(next.id) else { picked = next; break }
            await resolve(next.id)
        }
        guard let record = picked, let sub = try? await store.subscription(record.subscriptionID) else { return false }
        current = record.id
        defer { current = nil }
        let files = SystemFileOps()
        let fetcher = Fetcher(ytdlp: ytdlp, files: files, store: store, journal: journal, clock: clock,
                              finisher: Finisher(files: files, store: store, journal: journal, ffmpeg: ProcessFFmpeg()))
        let outcome = await fetcher.fetch(record, subscription: sub, settings: settings.fetchSettings(dataDirectory: dataDirectory))
        let wasOpen = gate.isOpen(at: Date())
        if VideoKey.isYouTube(record.id) || outcome == .deferred(.lowDisk) { gate.record(outcome, at: Date()) }
        if wasOpen, !gate.isOpen(at: Date()), let reason = gate.reason {
            journal.record(Entry(verb: .defer_, noun: .system, subject: "queue", outcome: .deferred,
                                 detail: "paused until \(gate.pausedUntil.map { "\($0)" } ?? "?"): \(reason.rawValue)"))
            await notify("Cylindarr paused fetching: \(reason.rawValue)")
        }
        if sub.isGrabList { await announce(record.id, outcome, subscription: sub.id) }
        if case .placed(let path) = outcome {
            await ensureArtwork(sub)
            await MediaServers(client: app.client, journal: journal).placed(relativePath: path, grab: sub.isGrabList, settings: settings)
            if sub.rules.retention != .keepAll { await retireByRule(sub.id) }
        }
        return true
    }

    /// A grab placed or failed, on the phone: the apps learn it this way,
    /// since a self-hosted server has no way to Apple's push service.
    func announce(_ key: String, _ outcome: Fetcher.Outcome, subscription: UUID) async {
        let title = (try? await store.video(key))?.title ?? key
        switch outcome {
        case .placed: await notify("Grabbed: \(title)", page: Links.video(key, in: subscription))
        case .failed(let cause): await notify("Grab failed: \(title) is \(cause.sentence).", page: Links.video(key, in: subscription))
        default: break
        }
    }

    /// `page` is a path such as `/settings`; with `CYLINDARR_PUBLIC_URL` set,
    /// tapping the notification opens it.
    func notify(_ message: String, page: String? = nil) async {
        guard !settings.ntfyURL.isEmpty else { return }
        let click = page.flatMap { page in Environment.get("CYLINDARR_PUBLIC_URL").flatMap { $0.isEmpty ? nil : $0 }.map { $0.trimmingSuffix("/") + page } }
        _ = try? await app.client.post(URI(string: settings.ntfyURL)) { req in
            if let click { req.headers.add(name: "Click", value: click) }
            req.body = ByteBuffer(string: message)
        }
    }

    // MARK: Subscriptions file

    /// Written to the library root after every change, so the subscriptions
    /// survive the database (docs/how-it-works.md).
    func exportSubscriptions() async {
        guard let subs = try? await SubscriptionModel.query(on: app.db).sort(\.$name).all() else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(subs.map(\.domain)) else { return }
        try? SystemFileOps().write(data, to: settings.libraryRoot + "/" + NamingScheme.subscriptionsFile)
    }
}

struct EngineKey: StorageKey { typealias Value = Engine }
struct JournalKey: StorageKey { typealias Value = Journal }

extension Application {
    var engine: Engine { storage[EngineKey.self]! }
    var journal: Journal { storage[JournalKey.self]! }
}

struct EngineLifecycle: LifecycleHandler {
    func didBootAsync(_ app: Application) async throws {
        if Environment.get("CYLINDARR_SCHEDULER") != "off" { await app.engine.start() }
    }

    func shutdownAsync(_ app: Application) async {
        await app.engine.stop()
    }
}
