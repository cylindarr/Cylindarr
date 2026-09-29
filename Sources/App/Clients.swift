import Vapor
import CylindarrKit

/// Feeds and channel pages over Vapor's client. Feeds are fetched with a
/// short timeout: a feed that hangs is a feed that failed, and the poll moves on.
struct VaporFeedClient: FeedClient {
    let client: Client

    func get(_ url: URL) async throws -> Data {
        let response: ClientResponse
        do {
            response = try await client.get(URI(string: url.absoluteString)) { req in
                req.headers.replaceOrAdd(name: .userAgent, value: "Mozilla/5.0 (compatible; Cylindarr)")
                req.timeout = .seconds(20)
            }
        } catch {
            throw HTTPFailure.transport("\(error)")
        }
        guard response.status == .ok, var body = response.body else { throw HTTPFailure.status(Int(response.status.code)) }
        return body.readData(length: body.readableBytes) ?? Data()
    }
}

/// Tells Plex and Jellyfin about a new file, so a new episode shows up at
/// once rather than at the next scheduled scan (real-time monitoring does
/// not see changes on a network share). Plex refreshes a folder; Jellyfin is
/// told the file's path.
struct MediaServers: Sendable {
    let client: Client
    let journal: Journal

    func placed(relativePath: String, grab: Bool, settings: AppSettings) async {
        let absolute = settings.libraryRoot + "/" + relativePath
        let folder = (absolute as NSString).deletingLastPathComponent
        let showFolder = grab ? folder : ((folder as NSString).deletingLastPathComponent)
        if !settings.plexURL.isEmpty, !settings.plexToken.isEmpty {
            let section = grab ? settings.plexGrabsSection : settings.plexSection
            if !section.isEmpty {
                var c = URLComponents(string: settings.plexURL.trimmingSuffix("/") + "/library/sections/\(section)/refresh")!
                c.queryItems = [URLQueryItem(name: "path", value: Self.map(showFolder, settings.plexPathMap)),
                                URLQueryItem(name: "X-Plex-Token", value: settings.plexToken)]
                let status = (try? await client.get(URI(string: c.url!.absoluteString)))?.status
                journal.record(Entry(verb: .notify, noun: .server, subject: "plex", outcome: status == .ok ? .ok : .failed,
                                     detail: status == .ok ? "refreshed \(showFolder)" : "refresh failed (\(status.map { "\($0.code)" } ?? "no answer"))"))
            }
        }
        if !settings.jellyfinURL.isEmpty, !settings.jellyfinKey.isEmpty {
            let theirs = Self.map(absolute, settings.jellyfinPathMap)
            struct Update: Content { let Path: String; let UpdateType: String }
            struct Body: Content { let Updates: [Update] }
            let status = (try? await client.post(URI(string: settings.jellyfinURL.trimmingSuffix("/") + "/Library/Media/Updated")) { req in
                req.headers.replaceOrAdd(name: "X-Emby-Token", value: settings.jellyfinKey)
                try req.content.encode(Body(Updates: [Update(Path: theirs, UpdateType: "Created")]))
            })?.status
            let ok = status.map { (200..<300).contains($0.code) } ?? false
            journal.record(Entry(verb: .notify, noun: .server, subject: "jellyfin", outcome: ok ? .ok : .failed,
                                 detail: ok ? "told of \((absolute as NSString).lastPathComponent)" : "update failed (\(status.map { "\($0.code)" } ?? "no answer"))"))
        }
    }
}

extension MediaServers {
    /// A path as a media server sees it, given `ours=theirs`: the prefix
    /// Cylindarr's container has for the library and the one the server's has.
    static func map(_ path: String, _ mapping: String) -> String {
        let map = mapping.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard map.count == 2, !map[0].isEmpty, path.hasPrefix(map[0]) else { return path }
        return map[1] + path.dropFirst(map[0].count)
    }
}

extension String {
    func trimmingSuffix(_ s: String) -> String { hasSuffix(s) ? String(dropLast(s.count)) : self }
}
