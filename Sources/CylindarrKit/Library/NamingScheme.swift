import Foundation

/// Where every file Cylindarr writes goes, relative to the library root:
///
///     Shows/<Show>/Season <YYYY>/s2026e092401 - <Title> [<id>].mp4   (+ .nfo, -thumb.jpg, .en.srt)
///     Grabs/<Title> (<YYYY>) [<id>]/<Title> (<YYYY>) [<id>].mp4      (+ .nfo, poster.jpg)
///
/// The id in brackets is the file's identity: it is how Adopt and Reconcile
/// know a file with no database, and it is yt-dlp's own convention. The title
/// a viewer sees comes from the NFO, so the bracket never shows.
public enum NamingScheme {
    public static let showsFolder = "Shows"
    public static let grabsFolder = "Grabs"
    public static let stagingFolder = ".cylindarr/staging"
    public static let subscriptionsFile = "cylindarr-subscriptions.json"

    /// A whole file name stays under this many bytes. Most filesystems allow
    /// 255; SMB clients and some NAS encryption layers allow less.
    public static let maxNameBytes = 200

    public static func showFolder(_ showName: String) -> String {
        PathSafety.truncate(PathSafety.clean(showName), toBytes: 120)
    }

    public static func seasonFolder(_ season: Int) -> String {
        "Season \(season)"
    }

    /// The stem every file of one episode shares: the media file adds `.mp4`,
    /// the NFO `.nfo`, the thumbnail `-thumb.jpg`, subtitles `.en.srt`.
    public static func episodeStem(number: EpisodeNumber, title: String, videoID: String) -> String {
        let prefix = "\(number) - "
        let suffix = " [\(videoID)]"
        // Room for the longest sidecar ending, `-thumb.jpg` or `.en-GB.srt`.
        let budget = maxNameBytes - prefix.utf8.count - suffix.utf8.count - 12
        return prefix + PathSafety.truncate(PathSafety.clean(title), toBytes: budget) + suffix
    }

    public static func episodeDirectory(show: String, number: EpisodeNumber) -> String {
        "\(showsFolder)/\(showFolder(show))/\(seasonFolder(number.season))"
    }

    public struct EpisodePaths: Equatable, Sendable {
        public let directory: String
        public let media: String
        public let nfo: String
        public let thumbnail: String
        public func subtitle(_ language: String) -> String {
            media.replacingOccurrences(of: ".mp4", with: ".\(language).srt", options: .anchored.union(.backwards))
        }
    }

    public static func episode(show: String, number: EpisodeNumber, title: String, videoID: String) -> EpisodePaths {
        let dir = episodeDirectory(show: show, number: number)
        let stem = episodeStem(number: number, title: title, videoID: videoID)
        return EpisodePaths(
            directory: dir, media: "\(dir)/\(stem).mp4", nfo: "\(dir)/\(stem).nfo",
            thumbnail: "\(dir)/\(stem)-thumb.jpg")
    }

    public static func grabStem(title: String, year: Int?, videoID: String) -> String {
        let yearPart = year.map { " (\($0))" } ?? ""
        let suffix = "\(yearPart) [\(videoID)]"
        let budget = maxNameBytes - suffix.utf8.count - 12
        return PathSafety.truncate(PathSafety.clean(title), toBytes: budget) + suffix
    }

    public static func grab(title: String, year: Int?, videoID: String) -> EpisodePaths {
        let stem = grabStem(title: title, year: year, videoID: videoID)
        let dir = "\(grabsFolder)/\(stem)"
        return EpisodePaths(
            directory: dir, media: "\(dir)/\(stem).mp4", nfo: "\(dir)/\(stem).nfo", thumbnail: "\(dir)/poster.jpg")
    }

    /// The id in a file name Cylindarr, yt-dlp or anything following yt-dlp's
    /// convention wrote: the last `[...]` holding an 11-character video id.
    public static func videoID(inFileName name: String) -> String? {
        let pattern = #"\[([A-Za-z0-9_-]{11})\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = name as NSString
        guard let match = regex.matches(in: name, range: NSRange(location: 0, length: ns.length)).last else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }
}
