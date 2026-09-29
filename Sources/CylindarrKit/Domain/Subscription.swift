import Foundation

public enum SubscriptionKind: String, Codable, Sendable {
    case channel, playlist
}

public enum SponsorBlockMode: String, Codable, Sendable {
    case cut, mark, off
}

public enum Quality: String, Codable, Sendable, CaseIterable {
    /// Up to 1080p. Every quality is encoded to HEVC once downloaded.
    case hd1080 = "1080p"
    case uhd2160 = "2160p"
    case hd720 = "720p"

    public var height: Int {
        switch self {
        case .hd1080: 1080
        case .uhd2160: 2160
        case .hd720: 720
        }
    }
}

public enum Retention: Codable, Sendable, Equatable {
    case keepAll
    case newest(Int)
    case days(Int)
}

/// What decides whether a video a subscription lists is wanted. The defaults
/// are Shorts out, finished livestreams in, 1080p, cut the sponsor, self-
/// promotion and interaction-reminder SponsorBlock segments, keep everything.
public struct Rules: Codable, Sendable, Equatable {
    public var cutoff: Date?
    public var titleInclude: String?
    public var titleExclude: String?
    public var minDuration: Int?
    public var maxDuration: Int?
    public var includeShorts: Bool
    public var includeLivestreams: Bool
    public var quality: Quality
    public var sponsorBlock: SponsorBlockMode
    public var sponsorBlockCategories: [String]
    public var retention: Retention
    public var autoCaptions: Bool

    public static let defaultSponsorBlockCategories = ["sponsor", "selfpromo", "interaction"]

    public init(
        cutoff: Date? = nil,
        titleInclude: String? = nil,
        titleExclude: String? = nil,
        minDuration: Int? = nil,
        maxDuration: Int? = nil,
        includeShorts: Bool = false,
        includeLivestreams: Bool = true,
        quality: Quality = .hd1080,
        sponsorBlock: SponsorBlockMode = .cut,
        sponsorBlockCategories: [String] = Rules.defaultSponsorBlockCategories,
        retention: Retention = .keepAll,
        autoCaptions: Bool = false
    ) {
        self.cutoff = cutoff
        self.titleInclude = titleInclude
        self.titleExclude = titleExclude
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.includeShorts = includeShorts
        self.includeLivestreams = includeLivestreams
        self.quality = quality
        self.sponsorBlock = sponsorBlock
        self.sponsorBlockCategories = sponsorBlockCategories
        self.retention = retention
        self.autoCaptions = autoCaptions
    }
}

/// A channel or playlist being followed. One subscription is one show, and the
/// show's name is `name`, never whatever yt-dlp reports as uploader or
/// playlist title. That is what keeps three playlists from one channel three
/// shows.
public struct Subscription: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: SubscriptionKind
    /// `UC...` for a channel, `PL...` (or `UU...`, `OL...`) for a playlist.
    public var youtubeID: String
    public var name: String
    public var rules: Rules
    public var enabled: Bool
    /// A grab list: a playlist whose videos are one-offs, filed under Grabs
    /// as films rather than as episodes of a show.
    public var isGrabList: Bool

    public init(
        id: UUID = UUID(),
        kind: SubscriptionKind,
        youtubeID: String,
        name: String,
        rules: Rules = Rules(),
        enabled: Bool = true,
        isGrabList: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.youtubeID = youtubeID
        self.name = name
        self.rules = rules
        self.enabled = enabled
        self.isGrabList = isGrabList
    }

    public var feedURL: URL {
        switch kind {
        case .channel: URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(youtubeID)")!
        case .playlist: URL(string: "https://www.youtube.com/feeds/videos.xml?playlist_id=\(youtubeID)")!
        }
    }

    /// What yt-dlp is asked to list. A channel's `/videos` tab, not the channel
    /// root, which yt-dlp expands into every tab (videos, Shorts, streams) as
    /// nested playlists.
    public var listingURL: URL {
        switch kind {
        case .channel: URL(string: "https://www.youtube.com/channel/\(youtubeID)/videos")!
        case .playlist: URL(string: "https://www.youtube.com/playlist?list=\(youtubeID)")!
        }
    }
}
