import Fluent
import Vapor
import CylindarrKit

/// From whatever was pasted to a subscription with a channel or playlist id
/// and a name. A handle is resolved to its `UC...` id from the channel page,
/// which costs one plain request and no yt-dlp call.
struct SubscriptionResolver {
    let req: Request

    struct Failure: Error { let message: String }

    static let grabsID = "cylindarr-grabs"

    func create(from raw: String, name: String?, backfill: Bool, grabList: Bool) async throws -> Subscription {
        guard let target = Identifier.parse(raw) else { throw Failure(message: "That is not a YouTube channel or playlist.") }
        let kind: SubscriptionKind
        let id: String
        switch target {
        case .channel(let c): kind = .channel; id = c
        case .playlist(let p): kind = .playlist; id = p
        case .handle(let h): kind = .channel; id = try await resolve("https://www.youtube.com/@\(h)")
        case .legacyName(let n): kind = .channel; id = try await resolve("https://www.youtube.com/c/\(n)")
        case .video: throw Failure(message: "That is a single video. Use Grab for one-offs.")
        case .other: throw Failure(message: "Subscriptions are YouTube only. Other sites work as one-off grabs.")
        }
        if try await SubscriptionModel.query(on: req.db).filter(\.$youtubeID == id).first() != nil {
            throw Failure(message: "Already followed.")
        }
        let feed = try? await VaporFeedClient(client: req.client).get(
            Subscription(kind: kind, youtubeID: id, name: "").feedURL)
        var youtubeTitle = feed.flatMap { try? FeedParser.parse($0).title }
        if youtubeTitle == nil {
            // The feed is down as often as not; the listing's title is the
            // same name, with " - Videos" on a channel's videos tab.
            let probe = Subscription(kind: kind, youtubeID: id, name: "")
            let run = await req.application.engine.ytdlp.run(["-J", "--flat-playlist", "--playlist-end", "1", "--no-warnings", probe.listingURL.absoluteString])
            if run.exitCode == 0, let listing = try? Listing.decode(run.stdout) {
                youtubeTitle = (listing.title ?? listing.channel).map { $0.hasSuffix(" - Videos") ? String($0.dropLast(9)) : $0 }
            }
        }
        let chosen = (name?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? youtubeTitle ?? id
        var rules = Rules()
        // A new subscription starts 30 days back unless its back catalogue is
        // asked for: the first night should not fetch 700 videos from one
        // address.
        if !backfill { rules.cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) }
        let sub = Subscription(kind: kind, youtubeID: id, name: chosen, rules: rules, isGrabList: grabList)
        try await SubscriptionModel(sub).create(on: req.db)
        req.application.journal.record(Entry(verb: .follow, noun: .subscription, subject: chosen, outcome: .ok,
                                             detail: "\(kind.rawValue) \(id)\(backfill ? ", whole back catalogue" : ", from 30 days ago")\(grabList ? ", as a grab list" : "")"))
        await req.application.engine.exportSubscriptions()
        if let model = try await SubscriptionModel.find(sub.id, on: req.db) {
            await req.application.engine.poll(model)
            // The back catalogue is listed after the page returns: a channel
            // with thousands of videos takes a minute or two.
            if backfill {
                let engine = req.application.engine
                Task { await engine.enumerate(model) }
            }
        }
        return sub
    }

    func resolve(_ page: String) async throws -> String {
        guard let url = URL(string: page), let html = try? await VaporFeedClient(client: req.client).get(url),
              let id = Identifier.channelID(inChannelPage: String(decoding: html, as: UTF8.self)) else {
            throw Failure(message: "Could not find that channel on YouTube.")
        }
        return id
    }

    /// A one-off: filed under Grabs as a film. Held by a built-in grab-list
    /// subscription that is never polled.
    func grab(_ raw: String) async throws -> String {
        guard case .video(let id) = Identifier.parse(raw) else {
            throw Failure(message: "Grab takes a single YouTube video for now.")
        }
        let grabs: SubscriptionModel
        if let existing = try await SubscriptionModel.query(on: req.db).filter(\.$youtubeID == Self.grabsID).first() {
            grabs = existing
        } else {
            grabs = SubscriptionModel(Subscription(kind: .playlist, youtubeID: Self.grabsID, name: "Grabs", enabled: false, isGrabList: true))
            try await grabs.create(on: req.db)
        }
        let store = FluentVideoStore(db: req.db)
        if var existing = try await store.video(id) {
            if case .placed = existing.state { throw Failure(message: "Already in the library.") }
            existing.state = .wanted
            existing.attempts = 0
            try await store.save(existing)
        } else {
            try await store.save(VideoRecord(id: id, subscriptionID: grabs.id!, title: id, uploaded: nil, state: .wanted, firstSeen: Date()))
        }
        req.application.journal.record(Entry(verb: .want, noun: .video, subject: id, outcome: .wanted, detail: "grab"))
        return id
    }
}
