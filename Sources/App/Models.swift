import Fluent
import Vapor
import CylindarrKit

/// A subscription row. The rules are stored as JSON: they are read and
/// written whole, and a new rule should not need a migration.
final class SubscriptionModel: Model, @unchecked Sendable {
    static let schema = "subscriptions"

    @ID(key: .id) var id: UUID?
    @Field(key: "kind") var kind: String
    @Field(key: "youtube_id") var youtubeID: String
    @Field(key: "name") var name: String
    @Field(key: "rules") var rules: String
    @Field(key: "enabled") var enabled: Bool
    @Field(key: "grab_list") var isGrabList: Bool
    @Field(key: "feed_failures") var feedFailures: Int
    @OptionalField(key: "last_polled") var lastPolled: Date?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(_ s: Subscription) {
        id = s.id
        update(from: s)
        feedFailures = 0
    }

    func update(from s: Subscription) {
        kind = s.kind.rawValue
        youtubeID = s.youtubeID
        name = s.name
        rules = String(decoding: (try? JSONEncoder().encode(s.rules)) ?? Data("{}".utf8), as: UTF8.self)
        enabled = s.enabled
        isGrabList = s.isGrabList
    }

    var domain: Subscription {
        Subscription(
            id: id!, kind: SubscriptionKind(rawValue: kind) ?? .channel, youtubeID: youtubeID, name: name,
            rules: (try? JSONDecoder().decode(Rules.self, from: Data(rules.utf8))) ?? Rules(),
            enabled: enabled, isGrabList: isGrabList)
    }
}

/// A video row. The state is split into columns so the front page can ask
/// "every failed video" and the scheduler "everything due" in SQL.
final class VideoModel: Model, @unchecked Sendable {
    static let schema = "videos"

    @ID(custom: "id", generatedBy: .user) var id: String?
    @Field(key: "subscription_id") var subscriptionID: UUID
    @Field(key: "title") var title: String
    @OptionalField(key: "uploaded") var uploaded: Date?
    @Field(key: "state") var state: String
    @OptionalField(key: "reason") var reason: String?
    @OptionalField(key: "until") var until: Date?
    @Field(key: "attempts") var attempts: Int
    @OptionalField(key: "season") var season: Int?
    @OptionalField(key: "episode") var episode: Int?
    @OptionalField(key: "path") var path: String?
    @Field(key: "first_seen") var firstSeen: Date
    @OptionalField(key: "last_cause") var lastCause: String?
    @OptionalField(key: "approx_uploaded") var approximatelyUploaded: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(_ r: VideoRecord) {
        id = r.id
        apply(r)
    }

    func apply(_ r: VideoRecord) {
        subscriptionID = r.subscriptionID
        title = r.title
        uploaded = r.uploaded
        state = r.state.name
        attempts = r.attempts
        season = r.number?.season
        episode = r.number?.episode
        path = r.path
        firstSeen = r.firstSeen
        lastCause = r.lastCause
        approximatelyUploaded = r.approximatelyUploaded
        switch r.state {
        case .skipped(let why): reason = why.rawValue; until = nil
        case .deferred(let cause, let u): reason = cause.rawValue; until = u
        case .failed(let cause): reason = cause.rawValue; until = nil
        default: reason = nil; until = nil
        }
    }

    var record: VideoRecord {
        let s: VideoState
        switch state {
        case "skipped": s = .skipped(SkipReason(rawValue: reason ?? "") ?? .byHand)
        case "wanted": s = .wanted
        case "deferred": s = .deferred(DeferCause(rawValue: reason ?? "") ?? .unknown, until: until ?? Date())
        case "failed": s = .failed(FailCause(rawValue: reason ?? "") ?? .unrecognised)
        case "placed": s = .placed
        case "retired": s = .retired
        default: s = .seen
        }
        let number = season.flatMap { se in episode.map { EpisodeNumber(season: se, episode: $0) } }
        return VideoRecord(id: id!, subscriptionID: subscriptionID, title: title, uploaded: uploaded, state: s,
                           attempts: attempts, number: number, path: path, firstSeen: firstSeen, lastCause: lastCause,
                           approximatelyUploaded: approximatelyUploaded)
    }
}

final class EntryModel: Model, @unchecked Sendable {
    static let schema = "entries"

    @ID(key: .id) var id: UUID?
    @Field(key: "at") var at: Date
    @Field(key: "verb") var verb: String
    @Field(key: "noun") var noun: String
    @Field(key: "subject") var subject: String
    @Field(key: "outcome") var outcome: String
    @Field(key: "detail") var detail: String

    init() {}

    init(_ e: Entry) {
        at = e.at
        verb = e.verb.rawValue
        noun = e.noun.rawValue
        subject = e.subject
        outcome = e.outcome.rawValue
        detail = e.detail
    }
}

final class SettingModel: Model, @unchecked Sendable {
    static let schema = "settings"

    @ID(custom: "key", generatedBy: .user) var id: String?
    @Field(key: "value") var value: String

    init() {}
    init(key: String, value: String) {
        id = key
        self.value = value
    }
}

enum Migrations {
    struct Initial: AsyncMigration {
        func prepare(on db: Database) async throws {
            try await db.schema(SubscriptionModel.schema)
                .id()
                .field("kind", .string, .required)
                .field("youtube_id", .string, .required)
                .field("name", .string, .required)
                .field("rules", .string, .required)
                .field("enabled", .bool, .required)
                .field("grab_list", .bool, .required)
                .field("feed_failures", .int, .required)
                .field("last_polled", .datetime)
                .field("created_at", .datetime)
                .unique(on: "youtube_id")
                .create()
            try await db.schema(VideoModel.schema)
                .field("id", .string, .identifier(auto: false))
                .field("subscription_id", .uuid, .required)
                .field("title", .string, .required)
                .field("uploaded", .datetime)
                .field("state", .string, .required)
                .field("reason", .string)
                .field("until", .datetime)
                .field("attempts", .int, .required)
                .field("season", .int)
                .field("episode", .int)
                .field("path", .string)
                .field("first_seen", .datetime, .required)
                .field("last_cause", .string)
                .field("updated_at", .datetime)
                .create()
            try await db.schema(EntryModel.schema)
                .id()
                .field("at", .datetime, .required)
                .field("verb", .string, .required)
                .field("noun", .string, .required)
                .field("subject", .string, .required)
                .field("outcome", .string, .required)
                .field("detail", .string, .required)
                .create()
            try await db.schema(SettingModel.schema)
                .field("key", .string, .identifier(auto: false))
                .field("value", .string, .required)
                .create()
        }

        func revert(on db: Database) async throws {
            for s in [SettingModel.schema, EntryModel.schema, VideoModel.schema, SubscriptionModel.schema] {
                try await db.schema(s).delete()
            }
        }
    }

    /// Listings' approximate upload dates, kept so a cutoff set later can be
    /// applied to what is already queued.
    struct ApproximateDates: AsyncMigration {
        func prepare(on db: Database) async throws {
            try await db.schema(VideoModel.schema).field("approx_uploaded", .datetime).update()
        }

        func revert(on db: Database) async throws {
            try await db.schema(VideoModel.schema).deleteField("approx_uploaded").update()
        }
    }

    static func register(_ app: Application) {
        app.migrations.add(Initial())
        app.migrations.add(ApproximateDates())
    }
}
