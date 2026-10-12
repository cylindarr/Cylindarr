import Fluent
import Vapor
import CylindarrKit

/// Where each thing on the pages links to: inside Cylindarr, the page that
/// shows it; outside, its page on YouTube.
enum Links {
    /// Blank for a key from another site, whose page only its record knows.
    static func youtube(video id: String) -> String {
        VideoKey.isYouTube(id) ? "https://www.youtube.com/watch?v=\(id)" : ""
    }

    /// A video's own page: YouTube's, or the other site's a grab came from.
    static func source(_ r: VideoRecord) -> String { r.sourceURL ?? youtube(video: r.id) }

    /// A subscription's page on YouTube. Blank for the built-in Grabs list,
    /// which is not a YouTube object.
    static func youtube(_ kind: String, _ youtubeID: String) -> String {
        guard youtubeID != SubscriptionResolver.grabsID else { return "" }
        return kind == SubscriptionKind.channel.rawValue
            ? "https://www.youtube.com/channel/\(youtubeID)"
            : "https://www.youtube.com/playlist?list=\(youtubeID)"
    }

    /// A video's row on its subscription's page.
    static func video(_ id: String, in subscription: UUID) -> String { "/subscriptions/\(subscription.uuidString)#v-\(id)" }

    /// One piece of a journal line's detail: text, or text that links.
    struct Segment: Content {
        let text: String
        let href: String
    }

    /// Everything a page of journal entries needs to link its subjects and
    /// the video ids in its details, looked up in two queries.
    struct Index {
        let subscriptions: [String: SubscriptionModel]
        let videos: [String: UUID]

        static func build(for entries: [EntryModel], on db: Database) async throws -> Index {
            let subs = try await SubscriptionModel.query(on: db).all()
            var byName: [String: SubscriptionModel] = [:]
            for s in subs where byName[s.name] == nil { byName[s.name] = s }
            var candidates = Set<String>()
            for e in entries {
                if VideoKey.isKey(e.subject) { candidates.insert(e.subject) }
                candidates.formUnion(tokens(in: e.detail).map(\.1))
            }
            var videos: [String: UUID] = [:]
            if !candidates.isEmpty {
                for m in try await VideoModel.query(on: db).filter(\.$id ~~ Array(candidates)).all() {
                    if let id = m.id { videos[id] = m.subscriptionID }
                }
            }
            return Index(subscriptions: byName, videos: videos)
        }

        /// The internal page for a subject, and its YouTube page, either blank.
        func subject(_ subject: String, noun: String, verb: String) -> (href: String, youtube: String) {
            if let sub = videos[subject] { return (Links.video(subject, in: sub), Links.youtube(video: subject)) }
            if let s = subscriptions[subject], let id = s.id, ["subscription", "show", "season", "episode"].contains(noun) {
                return ("/subscriptions/\(id.uuidString)", Links.youtube(s.kind, s.youtubeID))
            }
            if ["video", "episode", "grab"].contains(noun), Identifier.isVideoID(subject) {
                return ("", Links.youtube(video: subject))
            }
            switch (noun, subject) {
            case ("access", "cookies"): return ("/settings#cookies", "")
            case ("access", "yt-dlp"): return ("/settings#youtube", "")
            case ("access", _): return ("/#access", "")
            case ("server", _): return ("/settings#media-servers", "")
            case ("system", "encoding"): return ("/settings#encoding", "")
            case ("system", "settings"), ("system", "startup"): return ("/settings", "")
            case ("system", "queue"), ("run", "library"): return ("/", "")
            case ("run", _) where verb == "adopt":
                return ("/adopt?source=" + (subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""), "")
            default: return ("", "")
            }
        }

        /// The detail split so each known video id in it links to its row.
        func detail(_ text: String) -> [Segment] {
            var out: [Segment] = []
            var rest = text[...]
            for (range, id) in Links.tokens(in: text) {
                guard let sub = videos[id], range.lowerBound >= rest.startIndex else { continue }
                if rest.startIndex < range.lowerBound { out.append(Segment(text: String(text[rest.startIndex..<range.lowerBound]), href: "")) }
                out.append(Segment(text: id, href: Links.video(id, in: sub)))
                rest = text[range.upperBound...]
            }
            if !rest.isEmpty { out.append(Segment(text: String(rest), href: "")) }
            return out
        }
    }

    /// Every run of exactly eleven id characters. Most are words, not ids;
    /// only those the database knows as videos are linked.
    static func tokens(in text: String) -> [(Range<String.Index>, String)] {
        let pattern = #"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{11}(?![A-Za-z0-9_-])"#
        var out: [(Range<String.Index>, String)] = []
        var start = text.startIndex
        while let r = text.range(of: pattern, options: .regularExpression, range: start..<text.endIndex) {
            out.append((r, String(text[r])))
            start = r.upperBound
        }
        return out
    }
}
