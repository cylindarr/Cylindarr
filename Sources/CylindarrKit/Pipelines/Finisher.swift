import Foundation

/// Finish: from a staging folder holding `<id>.mp4`, `<id>.info.json`,
/// `<id>.jpg` and `<id>.<lang>.srt` to a placed episode. Consider again with
/// the full facts (the feed could not say it was a Short), encode it to HEVC
/// with its SponsorBlock segments cut (unless encoding is off), number it, rename every file into the
/// show, write its NFO and the show's if it has none, and drop what is left
/// in staging.
///
/// A video already placed (one downloaded again) keeps its episode number
/// and replaces its files, and is not considered again: it was wanted once.
public struct Finisher: Sendable {
    public let files: FileOps
    public let store: VideoStore
    public let journal: Journal
    public let ffmpeg: FFmpeg

    public init(files: FileOps, store: VideoStore, journal: Journal, ffmpeg: FFmpeg) {
        self.files = files
        self.store = store
        self.journal = journal
        self.ffmpeg = ffmpeg
    }

    public func finish(_ record: VideoRecord, subscription sub: Subscription, settings: FetchSettings) async -> Fetcher.Outcome {
        var record = record
        let staging = settings.staging(for: record.id)
        let root = settings.libraryRoot
        defer { try? files.remove(staging) }

        guard let names = try? files.contents(of: staging),
              let infoData = try? files.read(staging + "/\(record.id).info.json"),
              let info = try? VideoInfo.decode(infoData) else {
            return await fail(&record, detail: "yt-dlp finished but left no info.json in staging")
        }
        guard let media = names.first(where: { Adopter.mediaExtensions.contains(($0 as NSString).pathExtension.lowercased())
                                                 && ($0 as NSString).deletingPathExtension == record.id }) else {
            return await fail(&record, detail: "yt-dlp finished but left no media file in staging")
        }

        let previous = record.path
        if !sub.isGrabList, previous == nil, case .skip(let reason) = Consider.decide(Candidate(info), rules: sub.rules) {
            record.state = .skipped(reason)
            try? await store.save(record)
            journal.record(Entry(verb: .consider, noun: .video, subject: record.id, outcome: .skipped,
                                 detail: "\(reason.sentence), known only once fetched"))
            return .skipped(reason)
        }

        // Cutting needs an encode. With encoding off, the segments stay in
        // the file as the chapters yt-dlp marked them with.
        let cutList = sub.rules.sponsorBlock == .cut && settings.encode.encodes
            ? CutList(segments: info.sponsorblockChapters ?? [], categories: sub.rules.sponsorBlockCategories)
            : CutList([])
        let cuts = cutList.removed.count
        let encoded: String
        if settings.encode.encodes {
            encoded = staging + "/\(record.id).hevc.mp4"
            if let failure = await encode(staging + "/" + media, to: encoded, info: info, cuts: cutList,
                                          settings: settings, subject: record.id) {
                return await fail(&record, detail: failure)
            }
        } else {
            encoded = staging + "/" + media
        }
        let mediaExtension = (encoded as NSString).pathExtension

        let uploaded = info.uploaded ?? record.uploaded ?? Date()
        let paths: NamingScheme.EpisodePaths
        let nfo: String
        var number: EpisodeNumber?
        if sub.isGrabList {
            let year = EpisodeNumbering.calendar.component(.year, from: uploaded)
            // The record's key, not yt-dlp's id: from another site, the key
            // carries the site (see VideoKey).
            paths = NamingScheme.grab(title: info.title, year: year, videoID: record.id)
            nfo = NFOWriter.movie(.init(title: info.title, premiered: uploaded, plot: info.description,
                                        runtimeSeconds: info.duration.map { Int($0) }, studio: info.channel ?? info.uploader,
                                        videoID: record.id))
        } else {
            let taken = (try? await store.numbers(inShow: sub.name)) ?? []
            let n = record.number ?? EpisodeNumbering.assign([.init(id: info.id, uploaded: uploaded)], taken: taken)[info.id]!
            number = n
            paths = NamingScheme.episode(show: sub.name, number: n, title: info.title, videoID: info.id)
            nfo = NFOWriter.episode(.init(title: info.title, showTitle: sub.name, number: n, aired: uploaded,
                                          plot: info.description, runtimeSeconds: info.duration.map { Int($0) },
                                          studio: info.channel ?? info.uploader, videoID: info.id,
                                          thumb: (paths.thumbnail as NSString).lastPathComponent, sponsorBlockCuts: cuts))
        }

        do {
            try files.createDirectory(root + "/" + paths.directory)
            let mediaTarget = mediaExtension == "mp4" ? paths.media
                : (paths.media as NSString).deletingPathExtension + "." + mediaExtension
            // A title changed since it was first placed moves the episode:
            // the old files go before the new ones arrive.
            if let previous, previous != mediaTarget { removeEpisodeFiles(root + "/" + previous) }
            try files.rename(encoded, to: root + "/" + mediaTarget)
            var languages: Set<String> = []
            for name in names.sorted() where name != media {
                if name.hasSuffix(".jpg") {
                    try files.rename(staging + "/" + name, to: root + "/" + paths.thumbnail)
                } else if name.hasSuffix(".srt") {
                    let parts = name.split(separator: ".")
                    let lang = SubtitleCutter.languageTag(parts.count >= 3 ? String(parts[parts.count - 2]) : "en")
                    // Two English tracks become one sidecar: the first.
                    guard languages.insert(lang).inserted else { continue }
                    if cutList.isEmpty {
                        try files.rename(staging + "/" + name, to: root + "/" + paths.subtitle(lang))
                    } else {
                        let text = String(decoding: try files.read(staging + "/" + name), as: UTF8.self)
                        let cut = SubtitleCutter.cut(SubtitleCutter.parse(text), removing: cutList)
                        try files.write(Data(SubtitleCutter.render(cut).utf8), to: root + "/" + paths.subtitle(lang))
                    }
                }
            }
            try files.write(Data(nfo.utf8), to: root + "/" + paths.nfo)
            if !sub.isGrabList {
                let showDir = root + "/" + NamingScheme.showsFolder + "/" + NamingScheme.showFolder(sub.name)
                if !files.exists(showDir + "/tvshow.nfo") {
                    let show = NFOWriter.tvshow(.init(title: sub.name, studio: info.channel, youtubeID: sub.youtubeID))
                    try files.write(Data(show.utf8), to: showDir + "/tvshow.nfo")
                    journal.record(Entry(verb: .describe, noun: .show, subject: sub.name, outcome: .ok, detail: "wrote tvshow.nfo"))
                }
            }
            record.path = mediaTarget
        } catch {
            return await fail(&record, detail: "placing failed: \(error)")
        }

        record.title = info.title
        record.uploaded = uploaded
        record.number = number
        record.state = .placed
        record.lastCause = nil
        try? await store.save(record)
        let cutNote = cuts > 0 ? ", \(cuts) SponsorBlock cut\(cuts == 1 ? "" : "s")" : ""
        journal.record(Entry(verb: .place, noun: .episode, subject: sub.name, outcome: .ok,
                             detail: (record.path.map { ($0 as NSString).lastPathComponent } ?? "") + cutNote))
        return .placed(record.path ?? "")
    }

    /// Encodes `input` to `output`, cutting what `cuts` removes. Returns why
    /// it failed, or nil.
    func encode(_ input: String, to output: String, info: VideoInfo, cuts: CutList,
                settings: FetchSettings, subject: String) async -> String? {
        var chapters: String?
        if !cuts.isEmpty, let text = Transcode.chapters(info.chapters ?? [], cuts: cuts) {
            let path = settings.staging(for: subject) + "/\(subject).chapters.txt"
            do { try files.write(Data(text.utf8), to: path) } catch { return "writing chapters failed: \(error)" }
            chapters = path
        }
        let started = ContinuousClock.now
        var used = settings.encode
        func run(_ encode: EncodeSettings) async -> ProcessResult {
            await ffmpeg.run(Transcode.arguments(
                input: input, output: output, cuts: cuts,
                chapters: chapters, hasAudio: info.acodec != "none", audioIsAAC: info.acodec?.hasPrefix("mp4a") == true,
                settings: encode))
        }
        var result = await run(used)
        // Intel graphics before Ice Lake have no low-power HEVC encoder.
        if result.exitCode != 0, let fallback = used.withoutLowPower {
            journal.record(Entry(verb: .encode, noun: .video, subject: subject, outcome: .deferred,
                                 detail: "Quick Sync's low-power mode refused; trying its default mode"))
            used = fallback
            result = await run(used)
        }
        guard result.exitCode == 0, files.exists(output) else {
            let detail = "encoding failed with \(used.name): " + FailureClassifier.tail(of: result.stderr, lines: 2)
            journal.record(Entry(verb: .encode, noun: .video, subject: subject, outcome: .failed, detail: detail))
            return detail
        }
        // Nothing replaces a file until the replacement verifies: the encode
        // plays for as long as the source less the cuts. YouTube's duration
        // is whole seconds, hence the slack.
        let played = await ffmpeg.duration(of: output)
        let expected = info.duration.map { $0 - cuts.removedLength(of: $0) }
        if played == nil || expected.map({ abs(played! - $0) > 2 }) == true {
            let detail = "the encode plays for \(played.map { String(format: "%.1f", $0) } ?? "an unreadable length")"
                + (expected.map { String(format: " s, not %.1f s", $0) } ?? "")
            journal.record(Entry(verb: .encode, noun: .video, subject: subject, outcome: .failed, detail: detail))
            return detail
        }
        let took = Int((ContinuousClock.now - started).components.seconds)
        let cutNote = cuts.isEmpty ? "" : ", \(cuts.removed.count) cut\(cuts.removed.count == 1 ? "" : "s")"
        journal.record(Entry(verb: .encode, noun: .video, subject: subject, outcome: .ok,
                             detail: "HEVC with \(used.name) in \(took / 60)m \(took % 60)s\(cutNote)"))
        return nil
    }

    /// An episode's media and every sidecar named for it.
    func removeEpisodeFiles(_ mediaPath: String) {
        let directory = (mediaPath as NSString).deletingLastPathComponent
        let stem = ((mediaPath as NSString).lastPathComponent as NSString).deletingPathExtension
        for name in (try? files.contents(of: directory)) ?? [] where name.hasPrefix(stem + ".") || name.hasPrefix(stem + "-") {
            try? files.remove(directory + "/" + name)
        }
    }

    func fail(_ record: inout VideoRecord, detail: String) async -> Fetcher.Outcome {
        journal.record(Entry(verb: .place, noun: .episode, subject: record.id, outcome: .failed, detail: detail))
        return await Fetcher.fail(&record, .unrecognised, detail: detail, store: store, journal: journal)
    }
}
