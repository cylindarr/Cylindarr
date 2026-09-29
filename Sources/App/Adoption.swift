import Fluent
import Vapor
import CylindarrKit
import CylindarrSystem

/// Adopt, in the app: scan a tree, map its folders, read each video's facts
/// from its `.info.json` or NFO, show the plan, and run it. One plan at a
/// time, held by the actor between the page that shows it and the button
/// that runs it.
actor Adoption {
    struct Folder: Content {
        let path: String
        let videos: Int
        let identified: Int
        var destination: String
    }

    struct Prepared: Sendable {
        let source: String
        let plan: Adopter.Plan
        let destinations: [String: Adopter.Destination]
        let debris: [String]
        let loose: [String]
        let bytes: Int64
        let made: Date
    }

    private(set) var prepared: Prepared?
    private(set) var running = false
    private(set) var progress = ""

    /// The folders of a tree that hold videos, each with a suggested
    /// destination: a subscription of the same name, Grabs for a grab list,
    /// otherwise left alone.
    func scan(_ source: String, subscriptions: [String]) -> [Folder] {
        let (groups, _, _) = Adopter.group(SystemFileOps().walk(source))
        var byFolder: [String: (Int, Int)] = [:]
        for g in groups where g.media != nil {
            var c = byFolder[g.folder] ?? (0, 0)
            c.0 += 1
            if g.infoJSON != nil || g.nfo != nil || g.idInName != nil { c.1 += 1 }
            byFolder[g.folder] = c
        }
        return byFolder.keys.sorted().map { folder in
            let last = (folder as NSString).lastPathComponent
            let guess: String
            if let match = subscriptions.first(where: { $0.caseInsensitiveCompare(last) == .orderedSame }) {
                guess = "show:" + match
            } else if last.lowercased().contains("grab") || folder.isEmpty {
                guess = "grabs"
            } else {
                guess = "leave"
            }
            return Folder(path: folder, videos: byFolder[folder]!.0, identified: byFolder[folder]!.1, destination: guess)
        }
    }

    func prepare(source: String, mapping: [String: String], libraryRoot: String, store: FluentVideoStore,
                 subscriptions: [SubscriptionModel]) async -> Prepared {
        let files = SystemFileOps()
        let paths = files.walk(source)
        let (groups, loose, debris) = Adopter.group(paths)
        var destinations: [String: Adopter.Destination] = [:]
        for (folder, choice) in mapping {
            if choice == "grabs" { destinations[folder] = .grabs }
            else if choice.hasPrefix("show:") { destinations[folder] = .show(String(choice.dropFirst(5))) }
        }
        var facts: [String: Adopter.Facts] = [:]
        for g in groups where g.media != nil && Adopter.destination(for: g.folder, in: destinations) != nil {
            let key = g.folder + "/" + g.stem
            if let info = g.infoJSON, let data = try? files.read(source + "/" + info), let v = try? VideoInfo.decode(data),
               let f = Adopter.Facts(v) {
                facts[key] = f
            } else if let nfo = g.nfo, let data = try? files.read(source + "/" + nfo),
                      let f = NFOReader.facts(String(decoding: data, as: UTF8.self)) {
                facts[key] = f
            }
        }
        var taken: [String: Set<EpisodeNumber>] = [:]
        for case .show(let name) in Set(destinations.values) {
            taken[name] = (try? await store.numbers(inShow: name)) ?? []
        }
        var placedIDs: Set<String> = []
        for f in facts.values where (try? await store.video(f.id))?.state == .placed { placedIDs.insert(f.id) }
        let plan = Adopter.plan(groups: groups, facts: facts, destinations: destinations, taken: taken,
                                alreadyPlaced: placedIDs, sourcePrefix: source, libraryPrefix: libraryRoot)
        var bytes: Int64 = 0
        for case .move(let from, _) in plan.operations {
            bytes += ((try? FileManager.default.attributesOfItem(atPath: from)[.size]) as? NSNumber)?.int64Value ?? 0
        }
        let p = Prepared(source: source, plan: plan, destinations: destinations, debris: debris.map { source + "/" + $0 },
                         loose: loose, bytes: bytes, made: Date())
        prepared = p
        return p
    }

    /// Runs the prepared plan, one video's batch at a time. A batch whose
    /// media move fails is abandoned and reported; the others carry on. Each
    /// adopted video is recorded as placed, so Poll never fetches it again.
    func run(app: Application, journal: Journal) async {
        guard let p = prepared, !running else { return }
        running = true
        prepared = nil
        // The copying happens off the actor, so the pages that ask for
        // progress are never stuck behind a two-gigabyte file.
        await Adoption.execute(p, app: app, journal: journal, progress: { await self.setProgress($0) })
        running = false
    }

    func setProgress(_ text: String) { progress = text }

    nonisolated static func execute(_ p: Prepared, app: Application, journal: Journal,
                                    progress: @Sendable (String) async -> Void) async {
        let files = SystemFileOps()
        let db = app.db
        let store = FluentVideoStore(db: db)
        let subs = (try? await SubscriptionModel.query(on: db).all()) ?? []
        var grabsID = subs.first { $0.youtubeID == SubscriptionResolver.grabsID }?.id
        if grabsID == nil {
            let g = SubscriptionModel(Subscription(kind: .playlist, youtubeID: SubscriptionResolver.grabsID, name: "Grabs", enabled: false, isGrabList: true))
            try? await g.create(on: db)
            grabsID = g.id
        }
        let libraryRoot = await app.engine.settings.libraryRoot
        let placedByMedia = Dictionary(p.plan.placed.map { (libraryRoot + "/" + $0.media, $0) }, uniquingKeysWith: { a, _ in a })
        var done = 0, failed = 0, n = 0
        for batch in p.plan.batches {
            n += 1
            await progress("\(n) of \(p.plan.batches.count)")
            var ok = true
            var mediaTarget: String?
            for (i, op) in batch.enumerated() {
                do {
                    switch op {
                    case .move(let from, let to):
                        try files.relocate(from, to: to)
                        if i == 0 { mediaTarget = to }
                    case .write(let path, let contents):
                        try files.write(Data(contents.utf8), to: path)
                    case .remove(let path):
                        try files.remove(path)
                    }
                } catch {
                    journal.record(Entry(verb: .adopt, noun: .video, subject: "\(op)".prefix(60).description, outcome: .failed, detail: "\(error)"))
                    if i == 0 { ok = false; break }
                }
            }
            guard ok else { failed += 1; continue }
            done += 1
            // Record what was placed, keyed by the media target. A target with
            // another extension than .mp4 is matched by its stem.
            let target = mediaTarget ?? ""
            let placed = placedByMedia[target] ?? placedByMedia[String(target.dropLast((target as NSString).pathExtension.count)) + "mp4"]
            if let placed {
                let subID: UUID?
                switch placed.destination {
                case .grabs: subID = grabsID
                case .show(let name): subID = subs.first { $0.name == name }?.id
                }
                if let subID {
                    let relative = String(target.dropFirst(libraryRoot.count + 1))
                    try? await store.save(VideoRecord(id: placed.id, subscriptionID: subID, title: (relative as NSString).lastPathComponent,
                                                      uploaded: nil, state: .placed, number: placed.number, path: relative, firstSeen: Date()))
                }
            }
        }
        // A tvshow.nfo, and artwork, for every show adopted into.
        for case .show(let name) in Set(p.plan.placed.map(\.destination)) {
            guard let model = subs.first(where: { $0.name == name }) else { continue }
            let sub = model.domain
            let dir = libraryRoot + "/" + NamingScheme.showsFolder + "/" + NamingScheme.showFolder(name)
            if !files.exists(dir + "/tvshow.nfo") {
                try? files.write(Data(NFOWriter.tvshow(.init(title: name, youtubeID: sub.youtubeID)).utf8), to: dir + "/tvshow.nfo")
            }
            await app.engine.ensureArtwork(sub)
        }
        journal.record(Entry(verb: .adopt, noun: .run, subject: p.source, outcome: failed == 0 ? .ok : .failed,
                             detail: "\(done) videos adopted, \(failed) left where they were"))
        await app.engine.exportSubscriptions()
    }
}


struct AdoptionKey: StorageKey { typealias Value = Adoption }

extension Application {
    var adoption: Adoption {
        if let a = storage[AdoptionKey.self] { return a }
        let a = Adoption()
        storage[AdoptionKey.self] = a
        return a
    }
}

enum AdoptPages {
    struct ScanPage: Content {
        let version: String
        let source: String
        let folders: [Adoption.Folder]
        let choices: [Choice]
        let running: Bool
        let progress: String
    }

    struct Choice: Content {
        let value: String
        let label: String
    }

    struct PlanPage: Content {
        let version: String
        let source: String
        let summary: [Line]
        let problems: [String]
        let debris: [String]
        let loose: [String]
        let sample: [String]
        let gigabytes: String
        let batches: Int
    }

    struct Line: Content {
        let label: String
        let count: Int
    }
}

func adoptRoutes(_ app: Application) {
    app.get("adopt") { req async throws -> View in
        let source = req.query[String.self, at: "source"] ?? ""
        let subs = try await SubscriptionModel.query(on: req.db).sort(\.$name).all().filter { $0.youtubeID != SubscriptionResolver.grabsID }
        let folders = !source.isEmpty && FileManager.default.fileExists(atPath: source)
            ? await req.application.adoption.scan(source, subscriptions: subs.map(\.name)) : []
        var choices = [AdoptPages.Choice(value: "leave", label: "Leave alone"), AdoptPages.Choice(value: "grabs", label: "Grabs (films)")]
        choices += subs.map { AdoptPages.Choice(value: "show:" + $0.name, label: "Show: " + $0.name) }
        return try await req.view.render("adopt", AdoptPages.ScanPage(
            version: cylindarrVersion, source: source, folders: folders, choices: choices,
            running: await req.application.adoption.running, progress: await req.application.adoption.progress))
    }

    app.post("adopt", "plan") { req async throws -> View in
        // Each row carries its folder and its choice under its index, so a
        // folder name with brackets or dots survives the form encoding.
        struct Form: Content { var source: String; var folder: [String]?; var map: [String]? }
        let form = try req.content.decode(Form.self)
        var mapping: [String: String] = [:]
        for (i, folder) in (form.folder ?? []).enumerated() where i < (form.map ?? []).count {
            mapping[folder] = form.map![i]
        }
        let subs = try await SubscriptionModel.query(on: req.db).all()
        let p = await req.application.adoption.prepare(
            source: form.source, mapping: mapping, libraryRoot: await req.application.engine.settings.libraryRoot,
            store: FluentVideoStore(db: req.db), subscriptions: subs)
        var counts: [String: Int] = [:]
        for placed in p.plan.placed {
            switch placed.destination {
            case .show(let n): counts["Show: " + n, default: 0] += 1
            case .grabs: counts["Grabs", default: 0] += 1
            }
        }
        if !p.plan.placedByName.isEmpty { counts["Grabs, filed by name (no id)"] = p.plan.placedByName.count }
        let sample = p.plan.operations.prefix(60).map { op -> String in
            switch op {
            case .move(let a, let b): "move  \(a)\n   -> \(b)"
            case .write(let path, _): "write \(path)"
            case .remove(let path): "remove \(path)"
            }
        }
        return try await req.view.render("adopt-plan", AdoptPages.PlanPage(
            version: cylindarrVersion, source: p.source,
            summary: counts.sorted { $0.key < $1.key }.map { AdoptPages.Line(label: $0.key, count: $0.value) },
            problems: p.plan.problems.map { "\($0.kind.rawValue): \($0.path)" }, debris: p.debris, loose: p.loose,
            sample: sample, gigabytes: String(format: "%.1f", Double(p.bytes) / 1e9), batches: p.plan.batches.count))
    }

    app.post("adopt", "run") { req async -> Response in
        let app = req.application
        Task { await app.adoption.run(app: app, journal: app.journal) }
        return req.redirect(to: "/adopt")
    }
}
