import Foundation

/// Brings an existing tree (Pinchflat's, TubeSync's, anything yt-dlp wrote)
/// under management without downloading anything again. It works from what
/// is on disk: files grouped into videos by their shared stem, each video
/// identified by the id in its name, its `.info.json` or its NFO, and each
/// folder mapped to a subscription. The output is a plan, read before it runs.
public enum Adopter {
    public static let mediaExtensions: Set<String> = ["mp4", "mkv", "webm", "m4v", "mov", "avi", "m4a", "mp3", "opus"]

    /// Sidecar endings, longest first so `.info.json` is not read as `.json`.
    static let sidecarPatterns: [(pattern: String, kind: SidecarKind)] = [
        (#"\.info\.json$"#, .infoJSON),
        (#"-thumb\.(jpg|jpeg|png|webp)$"#, .thumbnail),
        (#"\.([A-Za-z]{2,3}(-[A-Za-z0-9]+)?)\.(srt|vtt|ass)$"#, .subtitle),
        (#"\.nfo$"#, .nfo),
        (#"\.(jpg|jpeg|png|webp)$"#, .thumbnail),
    ]

    public enum SidecarKind: String, Sendable, Equatable {
        case infoJSON, thumbnail, subtitle, nfo
    }

    /// One video's files, found together in one folder.
    public struct Group: Sendable, Equatable {
        public var folder: String
        public var stem: String
        public var media: String?
        public var sidecars: [String: SidecarKind]
        /// The id in the name: yt-dlp's `[id]`, or TubeSync's
        /// `_<id>_1080p-vp09-mp4a`.
        public var idInName: String? { Adopter.videoID(inName: stem) }

        public var nfo: String? { sidecars.first { $0.value == .nfo }?.key }
        public var infoJSON: String? { sidecars.first { $0.value == .infoJSON }?.key }
    }

    public static func videoID(inName name: String) -> String? {
        if let id = NamingScheme.videoID(inFileName: name) { return id }
        let pattern = #"_([A-Za-z0-9_-]{11})_(?:\d{3,4}p|premium|audio)(?:-|$)"#
        guard let r = name.range(of: pattern, options: .regularExpression) else { return nil }
        let match = name[r].dropFirst()
        return String(match.prefix(11))
    }

    /// Show-level files that belong to a folder rather than a video.
    static let showFiles: Set<String> = [
        "tvshow.nfo", "poster.jpg", "fanart.jpg", "banner.jpg", "folder.jpg", "season.nfo", "landscape.jpg",
    ]

    /// What an interrupted yt-dlp run leaves behind: `.part` and `.ytdl`
    /// files, and `.temp` intermediates from merging and subtitle conversion.
    /// A Pinchflat tree whose downloads the bot check interrupted has both
    /// kinds. Never media, never adopted, offered for removal.
    public static func isDebris(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".part") || lower.hasSuffix(".ytdl") || lower.hasSuffix(".concat")
            || lower.contains(".temp.") || lower.range(of: #"\.f\d+\.(mp4|webm|m4a)$"#, options: .regularExpression) != nil
    }

    /// Groups relative paths by folder and stem. Files that are neither media
    /// nor a recognised sidecar, and show-level files, come back as `loose`;
    /// interrupted-download leftovers as `debris`.
    public static func group(_ paths: [String]) -> (groups: [Group], loose: [String], debris: [String]) {
        var byKey: [String: Group] = [:]
        var loose: [String] = []
        var debris: [String] = []
        for path in paths {
            let (folder, name) = split(path)
            if isDebris(name) {
                debris.append(path)
                continue
            }
            if showFiles.contains(name.lowercased()) || name.hasPrefix(".") || name == "@eaDir" {
                loose.append(path)
                continue
            }
            let ext = (name as NSString).pathExtension.lowercased()
            if mediaExtensions.contains(ext) {
                let stem = (name as NSString).deletingPathExtension
                let key = folder + "/" + stem
                var g = byKey[key] ?? Group(folder: folder, stem: stem, media: nil, sidecars: [:])
                g.media = path
                byKey[key] = g
                continue
            }
            var matched = false
            for (pattern, kind) in sidecarPatterns {
                if let range = name.range(of: pattern, options: .regularExpression) {
                    let stem = String(name[..<range.lowerBound])
                    let key = folder + "/" + stem
                    var g = byKey[key] ?? Group(folder: folder, stem: stem, media: nil, sidecars: [:])
                    g.sidecars[path] = kind
                    byKey[key] = g
                    matched = true
                    break
                }
            }
            if !matched { loose.append(path) }
        }
        let groups = byKey.values.sorted { ($0.folder, $0.stem) < ($1.folder, $1.stem) }
        return (groups, loose.sorted(), debris.sorted())
    }

    static func split(_ path: String) -> (folder: String, name: String) {
        guard let slash = path.lastIndex(of: "/") else { return ("", path) }
        return (String(path[..<slash]), String(path[path.index(after: slash)...]))
    }

    /// What a video's own files say about it: from its `.info.json` when it
    /// has one, which every Pinchflat video does.
    public struct Facts: Sendable, Equatable {
        public var id: String
        public var title: String
        public var uploaded: Date
        public var duration: Int?
        public var description: String?
        public var uploader: String?
        public init(id: String, title: String, uploaded: Date, duration: Int? = nil, description: String? = nil,
                    uploader: String? = nil) {
            self.id = id
            self.title = title
            self.uploaded = uploaded
            self.duration = duration
            self.description = description
            self.uploader = uploader
        }

        public init?(_ info: VideoInfo) {
            guard let uploaded = info.uploaded else { return nil }
            self.init(id: info.id, title: info.title, uploaded: uploaded, duration: info.duration.map { Int($0) },
                      description: info.description, uploader: info.channel ?? info.uploader)
        }
    }

    /// Where a folder of the old tree goes.
    public enum Destination: Sendable, Hashable {
        case show(String)
        case grabs
    }

    public enum Operation: Sendable, Equatable {
        /// A rename within the library filesystem, or a copy and verify then
        /// delete across filesystems. FileOps decides which; the plan does not.
        case move(from: String, to: String)
        case write(path: String, contents: String)
        case remove(String)
    }

    public struct Problem: Sendable, Equatable {
        public enum Kind: String, Sendable { case unidentified, noMedia, unmappedFolder, duplicate }
        public let kind: Kind
        public let path: String
    }

    public struct Placed: Sendable, Equatable {
        public let id: String
        public let destination: Destination
        public let number: EpisodeNumber?
        public let media: String
    }

    public struct Plan: Sendable, Equatable {
        /// One batch per video, media first. A batch whose media move fails
        /// is abandoned, so a video's sidecars never move without it.
        public var batches: [[Operation]] = []
        public var operations: [Operation] { batches.flatMap { $0 } }
        public var placed: [Placed] = []
        /// Videos with no id anywhere, filed under Grabs by their file name
        /// because their folder was mapped there. Not recorded as videos:
        /// with no id there is nothing for Poll to recognise.
        public var placedByName: [String] = []
        public var problems: [Problem] = []
        public var looseFiles: [String] = []

        public var moveCount: Int { operations.filter { if case .move = $0 { true } else { false } }.count }
        public var removeCount: Int { operations.filter { if case .remove = $0 { true } else { false } }.count }
    }

    /// Builds the plan. `sourcePrefix` is the old tree's root, `libraryPrefix`
    /// the new library root; both are prepended to the relative paths in the
    /// operations. `facts` is keyed by `Group.folder + "/" + Group.stem`,
    /// already read from each group's `.info.json` by the caller. `taken` is
    /// the numbers already placed per show, so adoption into a show that
    /// already has episodes never collides with them.
    public static func plan(
        groups: [Group],
        facts: [String: Facts],
        destinations: [String: Destination],
        taken: [String: Set<EpisodeNumber>] = [:],
        alreadyPlaced: Set<String> = [],
        sourcePrefix: String,
        libraryPrefix: String
    ) -> Plan {
        var plan = Plan()
        var seen = alreadyPlaced
        var byShow: [String: [(Group, Facts)]] = [:]
        var grabs: [(Group, Facts)] = []

        for g in groups {
            let key = g.folder + "/" + g.stem
            guard let media = g.media else {
                plan.problems.append(Problem(kind: .noMedia, path: key))
                continue
            }
            guard let f = facts[key] else {
                if destination(for: g.folder, in: destinations) == .grabs {
                    placeByName(&plan, group: g, sourcePrefix: sourcePrefix, libraryPrefix: libraryPrefix)
                } else {
                    plan.problems.append(Problem(kind: .unidentified, path: media))
                }
                continue
            }
            guard let destination = destination(for: g.folder, in: destinations) else {
                plan.problems.append(Problem(kind: .unmappedFolder, path: g.folder))
                continue
            }
            if seen.contains(f.id) {
                plan.problems.append(Problem(kind: .duplicate, path: media))
                continue
            }
            seen.insert(f.id)
            switch destination {
            case .show(let name): byShow[name, default: []].append((g, f))
            case .grabs: grabs.append((g, f))
            }
        }

        for show in byShow.keys.sorted() {
            let items = byShow[show]!
            let numbers = EpisodeNumbering.assign(
                items.map { EpisodeNumbering.Upload(id: $0.1.id, uploaded: $0.1.uploaded) },
                taken: taken[show] ?? [])
            for (g, f) in items.sorted(by: { numbers[$0.1.id]! < numbers[$1.1.id]! }) {
                let number = numbers[f.id]!
                let paths = NamingScheme.episode(show: show, number: number, title: f.title, videoID: f.id)
                emit(&plan, group: g, facts: f, paths: paths, sourcePrefix: sourcePrefix, libraryPrefix: libraryPrefix,
                     nfo: NFOWriter.episode(.init(
                        title: f.title, showTitle: show, number: number, aired: f.uploaded, plot: f.description,
                        runtimeSeconds: f.duration, studio: f.uploader, videoID: f.id,
                        thumb: (paths.thumbnail as NSString).lastPathComponent)))
                plan.placed.append(Placed(id: f.id, destination: .show(show), number: number, media: paths.media))
            }
        }
        for (g, f) in grabs.sorted(by: { $0.1.uploaded < $1.1.uploaded }) {
            let year = EpisodeNumbering.calendar.component(.year, from: f.uploaded)
            let paths = NamingScheme.grab(title: f.title, year: year, videoID: f.id)
            emit(&plan, group: g, facts: f, paths: paths, sourcePrefix: sourcePrefix, libraryPrefix: libraryPrefix,
                 nfo: NFOWriter.movie(.init(
                    title: f.title, premiered: f.uploaded, plot: f.description, runtimeSeconds: f.duration,
                    studio: f.uploader, videoID: f.id)))
            plan.placed.append(Placed(id: f.id, destination: .grabs, number: nil, media: paths.media))
        }
        plan.problems.sort { ($0.kind.rawValue, $0.path) < ($1.kind.rawValue, $1.path) }
        return plan
    }

    /// The deepest mapped folder containing `folder`, so `shows/Some Channel`
    /// maps a video in `shows/Some Channel/Season 2019` too.
    public static func destination(for folder: String, in map: [String: Destination]) -> Destination? {
        var f = folder
        while true {
            if let d = map[f] { return d }
            guard let slash = f.lastIndex(of: "/") else { return map[""] }
            f = String(f[..<slash])
        }
    }

    /// `Carmack_Keynote_2021.mp4` becomes `Grabs/Carmack Keynote 2021/Carmack Keynote 2021.mp4`.
    static func placeByName(_ plan: inout Plan, group g: Group, sourcePrefix: String, libraryPrefix: String) {
        let title = PathSafety.clean(g.stem.replacingOccurrences(of: "_", with: " "))
        let stem = PathSafety.truncate(title, toBytes: NamingScheme.maxNameBytes - 16)
        let dir = "\(NamingScheme.grabsFolder)/\(stem)"
        let ext = ((g.media! as NSString).pathExtension).lowercased()
        var batch: [Operation] = [.move(from: sourcePrefix + "/" + g.media!, to: libraryPrefix + "/\(dir)/\(stem).\(ext)")]
        for (path, kind) in g.sidecars.sorted(by: { $0.key < $1.key }) where kind == .thumbnail {
            batch.append(.move(from: sourcePrefix + "/" + path, to: libraryPrefix + "/\(dir)/poster.jpg"))
        }
        let nfo = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<movie>\n" + NFOWriter.element("title", title) + "\n</movie>\n"
        batch.append(.write(path: libraryPrefix + "/\(dir)/\(stem).nfo", contents: nfo))
        plan.batches.append(batch)
        plan.placedByName.append(dir + "/\(stem).\(ext)")
    }

    static func emit(_ plan: inout Plan, group g: Group, facts f: Facts, paths: NamingScheme.EpisodePaths,
                     sourcePrefix: String, libraryPrefix: String, nfo: String) {
        var batch: [Operation] = []
        defer { plan.batches.append(batch) }
        let src = { (p: String) in sourcePrefix + "/" + p }
        let dst = { (p: String) in libraryPrefix + "/" + p }
        let ext = ((g.media! as NSString).pathExtension).lowercased()
        let mediaTarget = ext == "mp4" ? paths.media : String(paths.media.dropLast(3)) + ext
        batch.append(.move(from: src(g.media!), to: dst(mediaTarget)))
        for (path, kind) in g.sidecars.sorted(by: { $0.key < $1.key }) {
            switch kind {
            case .thumbnail:
                batch.append(.move(from: src(path), to: dst(paths.thumbnail)))
            case .subtitle:
                let name = (path as NSString).lastPathComponent
                let parts = name.split(separator: ".")
                let lang = SubtitleCutter.languageTag(parts.count >= 3 ? String(parts[parts.count - 2]) : "en")
                let ext = String(parts.last ?? "srt")
                let target = String(paths.subtitle(lang).dropLast(3)) + ext
                batch.append(.move(from: src(path), to: dst(target)))
            case .infoJSON, .nfo:
                // Read already; replaced by the NFO written below.
                batch.append(.remove(src(path)))
            }
        }
        batch.append(.write(path: dst(paths.nfo), contents: nfo))
    }
}
