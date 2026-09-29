import Fluent
import Vapor
import CylindarrKit
import CylindarrSystem

struct FluentVideoStore: VideoStore {
    let db: Database

    func video(_ id: String) async throws -> VideoRecord? {
        try await VideoModel.find(id, on: db)?.record
    }

    func save(_ record: VideoRecord) async throws {
        if let m = try await VideoModel.find(record.id, on: db) {
            m.apply(record)
            try await m.update(on: db)
        } else {
            try await VideoModel(record).create(on: db)
        }
    }

    func due(at now: Date, limit: Int) async throws -> [VideoRecord] {
        let rows = try await VideoModel.query(on: db)
            .group(.or) { g in
                g.filter(\.$state == "wanted")
                g.group(.and) { d in
                    d.filter(\.$state == "deferred")
                    d.filter(\.$until <= now)
                }
            }
            // New videos before placed ones being downloaded again (SQLite
            // sorts a null path first), so a re-encode of the library never
            // holds up a new upload.
            .sort(\.$path, .ascending)
            .sort(\.$firstSeen, .ascending)
            .limit(limit)
            .all()
        return rows.map(\.record)
    }

    func numbers(inShow show: String) async throws -> Set<EpisodeNumber> {
        let ids = try await SubscriptionModel.query(on: db).filter(\.$name == show).all().compactMap(\.id)
        guard !ids.isEmpty else { return [] }
        let rows = try await VideoModel.query(on: db).filter(\.$subscriptionID ~~ ids).filter(\.$season != nil).all()
        return Set(rows.compactMap { m in m.season.flatMap { s in m.episode.map { EpisodeNumber(season: s, episode: $0) } } })
    }

    func subscription(_ id: UUID) async throws -> Subscription? {
        try await SubscriptionModel.find(id, on: db)?.domain
    }
}

/// The journal: one fixed-column line on stdout for a log collector, and a row for the
/// pages. The row is written off the caller's path; a slow database never
/// slows a verb.
final class StdoutJournal: Journal, @unchecked Sendable {
    let db: Database
    init(db: Database) { self.db = db }

    func record(_ entry: Entry) {
        // Unbuffered, so a log collector sees the line when the verb happens.
        FileHandle.standardOutput.write(Data((entry.line + "\n").utf8))
        let db = self.db
        Task { try? await EntryModel(entry).create(on: db) }
    }
}

/// Settings live in the database and are edited on the settings page. The
/// environment can pin any of them, and a pinned setting shows as such.
struct AppSettings: Codable, Sendable, Equatable {
    var libraryRoot: String = "/library"
    var ytdlpPath: String = "/app/bin/yt-dlp"
    var potProvider: String = ""
    var proxy: String = ""
    var subtitleLanguages: String = "en"
    var minFreeGB: Int = 50
    var pollMinutes: Int = 30
    var pauseSecondsMin: Int = 60
    var pauseSecondsMax: Int = 180
    var fetching: Bool = true
    var plexURL: String = ""
    var plexToken: String = ""
    var plexSection: String = ""
    var plexGrabsSection: String = ""
    /// `/data/youtube=/media/youtube`: as jellyfinPathMap, for Plex.
    var plexPathMap: String = ""
    var jellyfinURL: String = ""
    var jellyfinKey: String = ""
    /// `/data/youtube=/media/youtube`: Cylindarr's path prefix and
    /// Jellyfin's for the same files, when its container mounts them
    /// elsewhere. Blank when both see the same paths.
    var jellyfinPathMap: String = ""
    var ntfyURL: String = ""
    var autoUpdate: Bool = true
    /// `auto`, `quicksync`, `vaapi`, `nvenc`, `software` or `none`.
    var encoder: String = "auto"
    /// The QP or CRF every encoder is given; see EncodeSettings.quality.
    var encodeQuality: Int = 24

    static let encoderChoices = ["auto", "quicksync", "vaapi", "nvenc", "software", "none"]

    init() {}

    /// Every field is optional in what is stored, so settings saved by an
    /// older version keep their values when a newer one adds a field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        libraryRoot = v(.libraryRoot, d.libraryRoot)
        ytdlpPath = v(.ytdlpPath, d.ytdlpPath)
        potProvider = v(.potProvider, d.potProvider)
        proxy = v(.proxy, d.proxy)
        subtitleLanguages = v(.subtitleLanguages, d.subtitleLanguages)
        minFreeGB = v(.minFreeGB, d.minFreeGB)
        pollMinutes = v(.pollMinutes, d.pollMinutes)
        pauseSecondsMin = v(.pauseSecondsMin, d.pauseSecondsMin)
        pauseSecondsMax = v(.pauseSecondsMax, d.pauseSecondsMax)
        fetching = v(.fetching, d.fetching)
        plexURL = v(.plexURL, d.plexURL)
        plexToken = v(.plexToken, d.plexToken)
        plexSection = v(.plexSection, d.plexSection)
        plexGrabsSection = v(.plexGrabsSection, d.plexGrabsSection)
        plexPathMap = v(.plexPathMap, d.plexPathMap)
        jellyfinURL = v(.jellyfinURL, d.jellyfinURL)
        jellyfinKey = v(.jellyfinKey, d.jellyfinKey)
        jellyfinPathMap = v(.jellyfinPathMap, d.jellyfinPathMap)
        ntfyURL = v(.ntfyURL, d.ntfyURL)
        autoUpdate = v(.autoUpdate, d.autoUpdate)
        encoder = v(.encoder, d.encoder)
        encodeQuality = v(.encodeQuality, d.encodeQuality)
    }

    static let environmentKeys: [String: WritableKeyPath<AppSettings, String>] = [
        "CYLINDARR_LIBRARY": \.libraryRoot,
        "CYLINDARR_YTDLP": \.ytdlpPath,
        "CYLINDARR_POT_PROVIDER_URL": \.potProvider,
        "CYLINDARR_PROXY": \.proxy,
        "CYLINDARR_PLEX_URL": \.plexURL,
        "CYLINDARR_PLEX_TOKEN": \.plexToken,
        "CYLINDARR_PLEX_SECTION": \.plexSection,
        "CYLINDARR_PLEX_GRABS_SECTION": \.plexGrabsSection,
        "CYLINDARR_PLEX_PATH_MAP": \.plexPathMap,
        "CYLINDARR_JELLYFIN_URL": \.jellyfinURL,
        "CYLINDARR_JELLYFIN_KEY": \.jellyfinKey,
        "CYLINDARR_JELLYFIN_PATH_MAP": \.jellyfinPathMap,
        "CYLINDARR_NTFY_URL": \.ntfyURL,
        "CYLINDARR_ENCODER": \.encoder,
    ]

    static func pinned() -> Set<String> {
        Set(environmentKeys.keys.filter { Environment.get($0)?.isEmpty == false })
    }

    static func load(_ db: Database) async -> AppSettings {
        var s = AppSettings()
        if let row = try? await SettingModel.find("settings", on: db),
           let stored = try? JSONDecoder().decode(AppSettings.self, from: Data(row.value.utf8)) {
            s = stored
        }
        for (key, path) in environmentKeys {
            if let v = Environment.get(key), !v.isEmpty { s[keyPath: path] = v }
        }
        return s
    }

    func save(_ db: Database) async throws {
        let json = String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
        if let row = try await SettingModel.find("settings", on: db) {
            row.value = json
            try await row.update(on: db)
        } else {
            try await SettingModel(key: "settings", value: json).create(on: db)
        }
    }

    /// The encoder the choice resolves to on this machine's devices.
    var resolvedEncoder: EncodeSettings.Encoder { ProcessFFmpeg.encoder(choice: encoder) }

    func fetchSettings(dataDirectory: String) -> FetchSettings {
        let cookies = dataDirectory + "/cookies.txt"
        return FetchSettings(
            libraryRoot: libraryRoot,
            cookiesPath: FileManager.default.fileExists(atPath: cookies) ? cookies : nil,
            proxy: proxy.isEmpty ? nil : proxy,
            potProvider: potProvider.isEmpty ? nil : potProvider,
            subtitleLanguages: subtitleLanguages.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            minFreeBytes: Int64(minFreeGB) * 1_000_000_000,
            encode: EncodeSettings(encoder: resolvedEncoder, quality: encodeQuality))
    }
}
