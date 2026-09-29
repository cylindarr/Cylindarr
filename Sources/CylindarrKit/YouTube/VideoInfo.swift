import Foundation

/// The part of yt-dlp's `-J` output Cylindarr reads for one video. Everything
/// optional that yt-dlp leaves out in some extractor state is optional here:
/// a decode failure over a missing field is how Pinchflat crashed on a
/// Technology Connections description.
public struct VideoInfo: Decodable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let description: String?
    /// `YYYYMMDD`, in UTC.
    public let uploadDate: String?
    public let timestamp: Int?
    public let releaseTimestamp: Int?
    public let duration: Double?
    public let channel: String?
    public let channelID: String?
    public let uploader: String?
    public let uploaderID: String?
    public let liveStatus: LiveStatus?
    public let availability: String?
    public let wasLive: Bool?
    public let mediaType: String?
    public let webpageURL: String?
    public let thumbnail: String?
    public let chapters: [Chapter]?
    public let categories: [String]?
    public let width: Int?
    public let height: Int?
    /// The downloaded audio's codec (`mp4a.40.2`, `opus`), or `none`.
    public let acodec: String?
    /// Present when yt-dlp was asked to cut or mark SponsorBlock segments.
    public let sponsorblockChapters: [SponsorBlockSegment]?

    public struct SponsorBlockSegment: Decodable, Sendable, Equatable {
        public let category: String?
        public let startTime: Double?
        public let endTime: Double?

        enum CodingKeys: String, CodingKey {
            case category
            case startTime = "start_time"
            case endTime = "end_time"
        }
    }

    public struct Chapter: Decodable, Sendable, Equatable {
        public let title: String
        public let startTime: Double
        public let endTime: Double

        enum CodingKeys: String, CodingKey {
            case title
            case startTime = "start_time"
            case endTime = "end_time"
        }
    }

    public enum LiveStatus: String, Decodable, Sendable {
        case notLive = "not_live"
        case isLive = "is_live"
        case isUpcoming = "is_upcoming"
        case wasLive = "was_live"
        case postLive = "post_live"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, timestamp, duration, channel, uploader, availability, thumbnail, chapters
        case categories, width, height, acodec
        case uploadDate = "upload_date"
        case releaseTimestamp = "release_timestamp"
        case channelID = "channel_id"
        case uploaderID = "uploader_id"
        case liveStatus = "live_status"
        case wasLive = "was_live"
        case mediaType = "media_type"
        case webpageURL = "webpage_url"
        case sponsorblockChapters = "sponsorblock_chapters"
    }

    public static func decode(_ data: Data) throws -> VideoInfo {
        try JSONDecoder().decode(VideoInfo.self, from: data)
    }

    /// When it went up. The timestamp where yt-dlp has one, since it orders
    /// same-day uploads; the upload date at noon UTC otherwise, so a date-only
    /// video lands on the right day in every time zone its viewers are in.
    public var uploaded: Date? {
        if let t = timestamp ?? releaseTimestamp { return Date(timeIntervalSince1970: TimeInterval(t)) }
        guard let d = uploadDate, d.count == 8, let y = Int(d.prefix(4)),
              let m = Int(d.dropFirst(4).prefix(2)), let day = Int(d.suffix(2)) else { return nil }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = day; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)
    }

    public var isShort: Bool {
        if mediaType == "short" { return true }
        if let u = webpageURL, u.contains("/shorts/") { return true }
        return false
    }

    public var isLivestreamRecording: Bool {
        liveStatus == .wasLive || liveStatus == .postLive || wasLive == true || mediaType == "livestream"
    }
}

/// yt-dlp's `-J --flat-playlist` output: a channel tab or a playlist, one
/// shallow entry per video. Flat entries carry no upload time, which is why
/// the feed, not the listing, supplies dates for new videos.
public struct Listing: Decodable, Sendable, Equatable {
    public let id: String
    public let title: String?
    public let channel: String?
    public let channelID: String?
    public let description: String?
    public let thumbnails: [Thumbnail]?
    public let entries: [ListingEntry]

    public struct Thumbnail: Decodable, Sendable, Equatable {
        public let id: String?
        public let url: String
        public let width: Int?
        public let height: Int?
    }

    enum CodingKeys: String, CodingKey {
        case id, title, channel, entries, description, thumbnails
        case channelID = "channel_id"
    }

    public static func decode(_ data: Data) throws -> Listing {
        try JSONDecoder().decode(Listing.self, from: data)
    }
}

public struct ListingEntry: Decodable, Sendable, Equatable {
    public let id: String
    public let title: String?
    public let duration: Double?
    public let url: String?
    public let liveStatus: VideoInfo.LiveStatus?
    public let availability: String?
    public let channelID: String?
    /// Only with `--extractor-args youtubetab:approximate_date`, and only as
    /// good as YouTube's "3 weeks ago": about a day on a channel's videos tab,
    /// a year on a playlist.
    public let timestamp: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, duration, url, availability, timestamp
        case liveStatus = "live_status"
        case channelID = "channel_id"
    }

    /// Private and deleted videos stay in playlists as placeholders with these
    /// titles and no duration.
    public var isPlaceholder: Bool {
        title == "[Private video]" || title == "[Deleted video]"
    }
}
