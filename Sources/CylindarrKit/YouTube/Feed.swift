import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One entry in a channel's or playlist's Atom feed: the newest fifteen
/// uploads, with the upload time the flat yt-dlp listing does not give.
public struct FeedEntry: Equatable, Sendable {
    public let videoID: String
    public let channelID: String?
    public let title: String
    public let published: Date
    public let updated: Date?
    public let description: String
}

public struct Feed: Equatable, Sendable {
    public let title: String
    public let channelID: String?
    public let playlistID: String?
    public let author: String?
    public let entries: [FeedEntry]
}

public enum FeedError: Error, Equatable, Sendable {
    /// Not a feed at all. YouTube answers roughly half of playlist feed
    /// requests with an HTML 404 page, and sometimes a 500, for playlists that
    /// exist and answer the next time. So this is never an alarm on its own.
    case notAFeed
    case malformed(String)
}

public enum FeedParser {
    public static func parse(_ data: Data) throws -> Feed {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            if !delegate.sawFeed { throw FeedError.notAFeed }
            throw FeedError.malformed(parser.parserError.map { "\($0)" } ?? "unknown")
        }
        guard delegate.sawFeed else { throw FeedError.notAFeed }
        return Feed(
            title: delegate.feedTitle,
            channelID: delegate.feedChannelID,
            playlistID: delegate.feedPlaylistID,
            author: delegate.feedAuthor,
            entries: delegate.entries)
    }

    /// A channel feed's own `yt:channelId` drops the `UC` prefix
    /// (`y0tKL1T7wFoYcxCe0xjN6Q` for `UCy0tKL1T7wFoYcxCe0xjN6Q`, seen
    /// 2026-09-27), while its entries and playlist feeds carry it in full.
    static func fullChannelID(_ raw: String) -> String {
        raw.count == 22 ? "UC" + raw : raw
    }

    nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    final class Delegate: NSObject, XMLParserDelegate {
        var sawFeed = false
        var feedTitle = ""
        var feedChannelID: String?
        var feedPlaylistID: String?
        var feedAuthor: String?
        var entries: [FeedEntry] = []

        private var path: [String] = []
        private var text = ""
        private var inEntry = false
        private var entryID = ""
        private var entryChannel: String?
        private var entryTitle = ""
        private var entryPublished: Date?
        private var entryUpdated: Date?
        private var entryDescription = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if path.isEmpty, name == "feed" { sawFeed = true }
            if name == "entry" {
                inEntry = true
                entryID = ""; entryChannel = nil; entryTitle = ""; entryPublished = nil; entryUpdated = nil
                entryDescription = ""
            }
            path.append(name)
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = path.dropLast().last
            if inEntry {
                switch name {
                case "yt:videoId": entryID = value
                case "yt:channelId": entryChannel = FeedParser.fullChannelID(value)
                case "title" where parent == "entry": entryTitle = value
                case "published" where parent == "entry": entryPublished = FeedParser.dateFormatter.date(from: value)
                case "updated" where parent == "entry": entryUpdated = FeedParser.dateFormatter.date(from: value)
                case "media:description": entryDescription = value
                case "entry":
                    inEntry = false
                    if !entryID.isEmpty, let published = entryPublished {
                        entries.append(FeedEntry(
                            videoID: entryID, channelID: entryChannel, title: entryTitle, published: published,
                            updated: entryUpdated, description: entryDescription))
                    }
                default: break
                }
            } else {
                switch name {
                case "title" where parent == "feed": feedTitle = value
                case "yt:channelId" where parent == "feed": feedChannelID = FeedParser.fullChannelID(value)
                case "yt:playlistId" where parent == "feed": feedPlaylistID = value
                case "name" where parent == "author" && path.count == 3: feedAuthor = value
                default: break
                }
            }
            path.removeLast()
            text = ""
        }
    }
}
