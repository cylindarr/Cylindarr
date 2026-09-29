import Crypto
import Fluent
import Vapor
import CylindarrKit
import CylindarrSystem

/// Verify, Update and artwork: the jobs that keep the way to YouTube and the
/// show folders in order, as opposed to the ones that fetch.
extension Engine {
    func verifyNow() async -> Verifier.Report {
        let report = await Verifier(ytdlp: ytdlp, http: VaporFeedClient(client: app.client), journal: journal, clock: clock)
            .verify(settings: settings.fetchSettings(dataDirectory: dataDirectory))
        await record(report)
        return report
    }

    /// A failing check pauses fetching for an hour, so the queue does not
    /// learn the same thing one video at a time. A passing one reopens a queue
    /// the bot check closed.
    func record(_ report: Verifier.Report) async {
        lastReport = report
        let jar = (try? String(contentsOfFile: dataDirectory + "/cookies.txt", encoding: .utf8)).map(CookieJar.parse)
        for message in cookieAlerts.messages(for: report, expiry: jar?.earliestRequiredExpiry,
                                             time: { Pages.short.string(from: $0) }, day: { Pages.day.string(from: $0) }) {
            await notify("Cylindarr: " + message, page: "/settings")
        }
        if !report.passes, let cause = report.cause, cause == .botCheck || cause == .rateLimited || cause == .streamForbidden {
            let wasOpen = gate.isOpen(at: Date())
            pauseGate(cause, for: 3600)
            if wasOpen { await notify("Cylindarr: YouTube access check failed (\(cause.rawValue)); fetching paused for an hour.") }
        } else if report.passes, !gate.isOpen(at: Date()), gate.reason == .botCheck || gate.reason == .streamForbidden {
            resumeGate()
        }
    }

    /// Daily. Downloads the latest yt-dlp for this platform, checks it
    /// against the release's SHA2-256SUMS, and switches only after Verify
    /// passes with the new binary. The old one stays, one version back.
    func updateYtDlp(force: Bool = false) async {
        guard settings.autoUpdate || force else { return }
        if AppSettings.pinned().contains("CYLINDARR_YTDLP") {
            journal.record(Entry(verb: .update, noun: .access, subject: "yt-dlp", outcome: .skipped,
                                 detail: "CYLINDARR_YTDLP pins the binary; not updating"))
            return
        }
        if lastReport?.ytdlpVersion == nil { _ = await verifyNow() }
        let client = app.client
        func get(_ url: String) async throws -> Data {
            let r = try await client.get(URI(string: url)) { req in
                req.headers.replaceOrAdd(name: .userAgent, value: "Cylindarr/\(cylindarrVersion)")
                req.headers.replaceOrAdd(name: .accept, value: "application/vnd.github+json")
                req.timeout = .seconds(120)
            }
            guard r.status == .ok, var body = r.body else { throw Abort(r.status) }
            return body.readData(length: body.readableBytes) ?? Data()
        }
        do {
            let release = try JSONDecoder().decode(YtDlpRelease.Release.self, from: try await get(YtDlpRelease.latestURL.absoluteString))
            let current = lastReport?.ytdlpVersion
            #if os(Linux)
            let os = "linux"
            #else
            let os = "macos"
            #endif
            #if arch(arm64)
            let arch = "aarch64"
            #else
            let arch = "x86_64"
            #endif
            guard let plan = YtDlpRelease.plan(release, current: current, asset: YtDlpRelease.assetName(os: os, arch: arch)) else {
                journal.record(Entry(verb: .update, noun: .access, subject: "yt-dlp", outcome: .ok, detail: "\(current ?? "?") is the latest"))
                return
            }
            let sums = String(decoding: try await get(plan.sumsURL), as: UTF8.self)
            guard let expected = YtDlpRelease.checksum(for: plan.assetName, in: sums) else {
                journal.record(Entry(verb: .update, noun: .access, subject: "yt-dlp", outcome: .failed, detail: "\(plan.version) has no checksum for \(plan.assetName)"))
                return
            }
            let binary = try await get(plan.binaryURL)
            let actual = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                journal.record(Entry(verb: .update, noun: .access, subject: "yt-dlp", outcome: .failed, detail: "\(plan.version) checksum mismatch; not installed"))
                return
            }
            let dir = dataDirectory + "/bin"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let path = dir + "/yt-dlp-" + plan.version
            FileManager.default.createFile(atPath: path, contents: binary, attributes: [.posixPermissions: 0o755])

            var trial = settings.fetchSettings(dataDirectory: dataDirectory)
            trial.cookiesPath = nil
            let env = ["HOME": dataDirectory, "PATH": Environment.get("PATH") ?? "/usr/local/bin:/usr/bin:/bin"]
            let report = await Verifier(ytdlp: ProcessYtDlp(executable: path, environment: env), http: VaporFeedClient(client: client),
                                        journal: journal, clock: clock).verify(settings: trial)
            guard report.passes else {
                journal.record(Entry(verb: .update, noun: .access, subject: "yt-dlp", outcome: .failed,
                                     detail: "\(plan.version) downloaded and checked but failed Verify; staying on \(current ?? "?")"))
                return
            }
            let previous = settings.ytdlpPath
            var s = await AppSettings.load(app.db)
            s.ytdlpPath = path
            try await s.save(app.db)
            await reload()
            await record(report)
            // Keep this one and the one before it.
            let keep: Set<String> = [path, previous]
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where !keep.contains(dir + "/" + name) {
                try? FileManager.default.removeItem(atPath: dir + "/" + name)
            }
            journal.record(Entry(verb: .update, noun: .access, subject: "yt-dlp", outcome: .ok,
                                 detail: "\(current ?? "?") -> \(plan.version), checksum and Verify passed"))
        } catch {
            journal.record(Entry(verb: .update, noun: .access, subject: "yt-dlp", outcome: .failed, detail: "\(error)"))
        }
    }

    /// A show folder's poster, fanart and banner, once, when it has none.
    func ensureArtwork(_ sub: Subscription) async {
        guard !sub.isGrabList else { return }
        let dir = settings.libraryRoot + "/" + NamingScheme.showsFolder + "/" + NamingScheme.showFolder(sub.name)
        guard !FileManager.default.fileExists(atPath: dir + "/poster.jpg") else { return }
        func listing(_ url: URL) async -> Listing? {
            var args = ["-J", "--flat-playlist", "--playlist-end", "1", "--no-warnings"]
            if !settings.proxy.isEmpty { args += ["--proxy", settings.proxy] }
            let r = await ytdlp.run(args + [url.absoluteString])
            return r.exitCode == 0 ? try? Listing.decode(r.stdout) : nil
        }
        var art: [String: URL] = [:]
        guard let own = await listing(sub.listingURL) else {
            journal.record(Entry(verb: .describe, noun: .show, subject: sub.name, outcome: .failed, detail: "could not list the channel for artwork"))
            return
        }
        switch sub.kind {
        case .channel:
            art = Artwork.forChannel(own.thumbnails ?? [])
        case .playlist:
            art = Artwork.forPlaylist(own.thumbnails ?? [])
            if let channel = own.channelID,
               let theirs = await listing(Subscription(kind: .channel, youtubeID: channel, name: "").listingURL),
               let poster = Artwork.forChannel(theirs.thumbnails ?? [])["poster.jpg"] {
                art["poster.jpg"] = poster
            }
        }
        var written: [String] = []
        for (name, url) in art.sorted(by: { $0.key < $1.key }) {
            guard let r = try? await app.client.get(URI(string: url.absoluteString)), r.status == .ok, var body = r.body,
                  let data = body.readData(length: body.readableBytes), !data.isEmpty else { continue }
            if (try? SystemFileOps().write(data, to: dir + "/" + name)) != nil { written.append(name) }
        }
        journal.record(Entry(verb: .describe, noun: .show, subject: sub.name, outcome: written.isEmpty ? .failed : .ok,
                             detail: written.isEmpty ? "no artwork found" : "wrote " + written.joined(separator: ", ")))
    }
}

extension Engine {
    /// Retire by date: set the subscription's cutoff to `from` and delete
    /// every placed episode uploaded before it, with all its sidecars. Each
    /// is recorded as retired, so no poll or listing fetches it again.
    /// Returns how many episodes and bytes went.
    func keepOnly(from: Date, subscription id: UUID) async -> (Int, Int64) {
        guard let model = try? await SubscriptionModel.find(id, on: app.db) else { return (0, 0) }
        var sub = model.domain
        sub.rules.cutoff = from
        model.update(from: sub)
        try? await model.update(on: app.db)
        let rows = (try? await VideoModel.query(on: app.db).filter(\.$subscriptionID == id).all()) ?? []
        var count = 0
        var bytes: Int64 = 0
        for row in rows {
            var r = row.record
            let when = r.uploaded ?? r.number.flatMap { n -> Date? in
                var c = DateComponents()
                c.year = n.season; c.month = n.month; c.day = n.day; c.hour = 12
                return EpisodeNumbering.calendar.date(from: c)
            }
            guard let when, when < from else { continue }
            switch r.state {
            case .placed:
                guard r.path != nil else { continue }
                bytes += removeEpisode(r)
                r.state = .retired
                count += 1
                journal.record(Entry(verb: .retire, noun: .episode, subject: r.id, outcome: .ok, detail: "before \(Pages.day.string(from: from)): \(r.title)"))
            case .wanted, .deferred, .failed, .seen:
                r.state = .skipped(.beforeCutoff)
            default:
                continue
            }
            row.apply(r)
            try? await row.update(on: app.db)
        }
        journal.record(Entry(verb: .retire, noun: .subscription, subject: sub.name, outcome: .ok,
                             detail: "kept from \(Pages.day.string(from: from)); \(count) episodes deleted, \(bytes / 1_000_000_000) GB"))
        await exportSubscriptions()
        await reconsider(id)
        return (count, bytes)
    }
}

extension Engine {
    /// Deletes a placed episode's media and every sidecar named for it, and
    /// its season folder when that leaves it empty. Returns the bytes freed.
    func removeEpisode(_ r: VideoRecord) -> Int64 {
        guard let path = r.path else { return 0 }
        let files = SystemFileOps()
        let full = settings.libraryRoot + "/" + path
        let dir = (full as NSString).deletingLastPathComponent
        let stem = ((full as NSString).lastPathComponent as NSString).deletingPathExtension
        var bytes: Int64 = 0
        for name in (try? files.contents(of: dir)) ?? [] where name.hasPrefix(stem) {
            bytes += ((try? FileManager.default.attributesOfItem(atPath: dir + "/" + name)[.size]) as? NSNumber)?.int64Value ?? 0
            try? files.remove(dir + "/" + name)
        }
        if ((try? files.contents(of: dir)) ?? []).isEmpty { try? files.remove(dir) }
        return bytes
    }

    /// Retire by rule: for every subscription that keeps only its newest
    /// episodes or its last days (or the one given), delete what the rule no
    /// longer keeps and record it as retired, so it is never fetched again.
    func retireByRule(_ only: UUID? = nil) async {
        guard let subs = try? await SubscriptionModel.query(on: app.db).all() else { return }
        for model in subs where only == nil || model.id == only {
            let sub = model.domain
            guard sub.rules.retention != .keepAll, !sub.isGrabList, let id = model.id else { continue }
            let rows = (try? await VideoModel.query(on: app.db).filter(\.$subscriptionID == id).filter(\.$state == "placed").all()) ?? []
            let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id!, $0) })
            let retire = RetireByRule.toRetire(rows.map(\.record), retention: sub.rules.retention, now: Date())
            guard !retire.isEmpty else { continue }
            var bytes: Int64 = 0
            for var r in retire {
                guard let row = byID[r.id] else { continue }
                bytes += removeEpisode(r)
                r.state = .retired
                row.apply(r)
                try? await row.update(on: app.db)
                journal.record(Entry(verb: .retire, noun: .episode, subject: r.id, outcome: .ok, detail: "past the retention rule: \(r.title)"))
            }
            journal.record(Entry(verb: .retire, noun: .subscription, subject: sub.name, outcome: .ok,
                                 detail: "\(retire.count) episodes past the retention rule deleted, \(bytes / 1_000_000) MB"))
        }
    }
}

extension Engine {
    /// Decide again what a subscription still has waiting, after its rules
    /// change. Videos queued with no date at all (found by a listing before
    /// approximate dates were kept) get one from a fresh listing first.
    func reconsider(_ id: UUID) async {
        guard let model = try? await SubscriptionModel.find(id, on: app.db) else { return }
        let sub = model.domain
        guard !sub.isGrabList else { return }
        let rows = (try? await VideoModel.query(on: app.db).filter(\.$subscriptionID == id)
            .filter(\.$state ~~ ["wanted", "deferred", "failed"]).all()) ?? []
        guard !rows.isEmpty else { return }
        if sub.rules.cutoff != nil, rows.contains(where: { $0.uploaded == nil && $0.approximatelyUploaded == nil }) {
            let depth = min(rows.count + 40, 400)
            let run = await ytdlp.run(["-J", "--flat-playlist", "--playlist-end", String(depth), "--no-warnings",
                                       "--extractor-args", "youtubetab:approximate_date", sub.listingURL.absoluteString])
            if run.exitCode == 0, let listing = try? Listing.decode(run.stdout) {
                let dates = Dictionary(listing.entries.compactMap { e in e.timestamp.map { (e.id, Date(timeIntervalSince1970: TimeInterval($0))) } },
                                       uniquingKeysWith: { a, _ in a })
                for row in rows where row.uploaded == nil && row.approximatelyUploaded == nil {
                    row.approximatelyUploaded = dates[row.id!]
                }
            }
        }
        let changed = Reconsider.changes(rows.map(\.record), rules: sub.rules, now: Date())
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id!, $0) })
        for r in changed {
            guard let row = byID[r.id] else { continue }
            row.apply(r)
            try? await row.update(on: app.db)
            if case .skipped(let reason) = r.state {
                journal.record(Entry(verb: .consider, noun: .video, subject: r.id, outcome: .skipped, detail: "\(reason.sentence), after the rules changed: \(r.title)"))
            }
        }
        // Rows given a date but not skipped still keep the date.
        for row in rows where !changed.contains(where: { $0.id == row.id }) && row.hasChanges {
            try? await row.update(on: app.db)
        }
        journal.record(Entry(verb: .consider, noun: .subscription, subject: sub.name, outcome: .ok,
                             detail: "rules changed; \(changed.count) of \(rows.count) waiting are now skipped"))
    }
}

extension Engine {
    /// Queue every placed video to be downloaded and encoded again, as when
    /// the encoding changes. Each keeps its number and its file until the new
    /// one replaces it, and new uploads still go first. Returns how many.
    func downloadLibraryAgain() async -> Int {
        let rows = (try? await VideoModel.query(on: app.db).filter(\.$state == "placed").all()) ?? []
        var count = 0
        for row in rows where row.path != nil {
            var r = row.record
            r.state = .wanted
            r.attempts = 0
            row.apply(r)
            try? await row.update(on: app.db)
            count += 1
        }
        journal.record(Entry(verb: .want, noun: .run, subject: "library", outcome: .wanted,
                             detail: "\(count) placed videos to download and encode again"))
        return count
    }
}
