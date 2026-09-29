import Foundation
import Testing
@testable import CylindarrKit

@Suite struct PollerTests {
    let tc = Subscription(kind: .channel, youtubeID: "UCy0tKL1T7wFoYcxCe0xjN6Q", name: "Technology Connections",
                          rules: Rules(cutoff: Fixture.date("2026-09-05T00:00:00Z")))

    @Test func theFeedFindsTheNewUploadAndTheCutoffSkipsTheRest() async throws {
        let feeds = FakeFeeds()
        feeds.responses[tc.feedURL] = .success(Fixture.data("feeds/channel-technology-connections.xml"))
        let store = MemoryStore(), journal = CollectingJournal()
        let poller = Poller(feeds: feeds, ytdlp: FakeYtDlp(), store: store, journal: journal, clock: FixedClock(Fixture.date("2026-09-27T12:00:00Z")))
        let r = await poller.poll(tc, feedFailures: 0)
        #expect(r.source == .feed)
        #expect(r.new.count == 15)
        #expect(r.wanted == ["0KoeY54M5VA"])
        let v = try #require(await store.all()["0KoeY54M5VA"])
        #expect(v.state == .wanted)
        #expect(v.uploaded == Fixture.date("2026-09-24T16:57:27Z"))
        #expect(journal.entries.last?.detail == "15 new, 1 wanted: 0KoeY54M5VA")

        // The second poll sees nothing new and writes one line saying so.
        let again = await poller.poll(tc, feedFailures: 0)
        #expect(again.new.isEmpty)
        #expect(journal.entries.last?.detail == "nothing new")
    }

    /// Feed and listing both failing is a deferral with the feed's reason,
    /// not an alarm.
    @Test func whenNeitherAnswersThePollDefers() async {
        let yt = FakeYtDlp()
        yt.steps = [.init(result: FakeYtDlp.fail("ERROR: [youtube:tab] Unable to download API page: HTTP Error 503"))]
        let journal = CollectingJournal()
        let poller = Poller(feeds: FakeFeeds(), ytdlp: yt, store: MemoryStore(), journal: journal, clock: FixedClock(Date()))
        let r = await poller.poll(tc, feedFailures: 0)
        #expect(r.source == .none && r.feedFailed)
        #expect(r.feedError == "HTTP 404")
        #expect(yt.calls.count == 1)
        #expect(journal.entries.last?.outcome == .deferred)
        #expect(journal.entries.last?.detail == "feed did not answer (HTTP 404, 1 in a row)")
    }

    @Test func whenTheFeedFailsTheListingIsUsed() async throws {
        let dl = Subscription(kind: .playlist, youtubeID: "PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj", name: "Dream Logic")
        let yt = FakeYtDlp()
        yt.steps = [.init(result: FakeYtDlp.ok(Fixture.data("ytdlp/flat-playlist-dream-logic.json")))]
        let store = MemoryStore()
        let poller = Poller(feeds: FakeFeeds(), ytdlp: yt, store: store, journal: CollectingJournal(), clock: FixedClock(Date()))
        let r = await poller.poll(dl, feedFailures: 0)
        #expect(r.source == .listing)
        #expect(r.wanted.count == 5)
        #expect(yt.calls.first?.contains("--flat-playlist") == true)
        #expect(yt.calls.first?.last == "https://www.youtube.com/playlist?list=PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj")
        // No upload time from a listing: the cutoff is applied at fetch time.
        #expect(await store.all()["snyvQ9COmb8"]?.uploaded == nil)
    }
}

@Suite struct EnumerateTests {
    /// The whole listing, with no depth limit; new videos considered, and
    /// one skipped earlier for its date wanted again once the cutoff is gone.
    @Test func theWholeListingIsConsidered() async throws {
        let dl = Subscription(kind: .playlist, youtubeID: "PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj", name: "Dream Logic")
        let yt = FakeYtDlp()
        yt.steps = [.init(result: FakeYtDlp.ok(Fixture.data("ytdlp/flat-playlist-dream-logic.json")))]
        let store = MemoryStore(), journal = CollectingJournal()
        await store.add(dl)
        try await store.save(VideoRecord(id: "snyvQ9COmb8", subscriptionID: dl.id, title: "t", uploaded: nil,
                                         state: .skipped(.beforeCutoff), firstSeen: Date()))
        let poller = Poller(feeds: FakeFeeds(), ytdlp: yt, store: store, journal: journal, clock: FixedClock(Date()))
        let r = await poller.enumerate(dl)
        #expect(r.source == .listing)
        #expect(!(yt.calls.first?.contains("--playlist-end") ?? true))
        #expect(r.new.count == 4)
        #expect(r.wanted.count == 5)
        #expect(await store.all()["snyvQ9COmb8"]?.state == .wanted)
        #expect(journal.entries.last?.verb == .enumerate)
        #expect(journal.entries.last?.detail == "5 listed, 4 new, 5 wanted")
    }
}

@Suite struct FetcherTests {
    let root = "/data/youtube"
    let now = Fixture.date("2026-09-27T12:00:00Z")
    let dreamLogic = Subscription(kind: .playlist, youtubeID: "PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj", name: "Dream Logic")

    func rig(cookies: Bool = false) async -> (Fetcher, FakeYtDlp, MemoryFiles, MemoryStore, CollectingJournal, FetchSettings, VideoRecord) {
        let yt = FakeYtDlp(), files = MemoryFiles(), store = MemoryStore(), journal = CollectingJournal()
        await store.add(dreamLogic)
        let finisher = Finisher(files: files, store: store, journal: journal, ffmpeg: FakeFFmpeg(files: files, played: 265.4))
        let fetcher = Fetcher(ytdlp: yt, files: files, store: store, journal: journal, clock: FixedClock(now), finisher: finisher)
        let settings = FetchSettings(libraryRoot: root, cookiesPath: cookies ? "/app/data/cookies.txt" : nil,
                                     potProvider: "http://pot:4416")
        let record = VideoRecord(id: "snyvQ9COmb8", subscriptionID: dreamLogic.id, title: "When AI Stops Feeling Magical",
                                 uploaded: nil, state: .wanted, firstSeen: now)
        return (fetcher, yt, files, store, journal, settings, record)
    }

    /// What a real run leaves in staging.
    func writesStaging(_ files: MemoryFiles, _ settings: FetchSettings) -> ([String]) -> Void {
        { _ in
            let s = settings.staging(for: "snyvQ9COmb8")
            files.files[s + "/snyvQ9COmb8.mp4"] = Data("video".utf8)
            files.files[s + "/snyvQ9COmb8.info.json"] = Fixture.data("ytdlp/video-dream-logic-snyvQ9COmb8.json")
            files.files[s + "/snyvQ9COmb8.jpg"] = Data("jpg".utf8)
        }
    }

    func writesSubtitles(_ files: MemoryFiles, _ settings: FetchSettings, code: String = "en") -> ([String]) -> Void {
        { _ in files.files[settings.staging(for: "snyvQ9COmb8") + "/snyvQ9COmb8.\(code).srt"] = Data("1\n00:00:10,000 --> 00:00:12,000\nhello\n".utf8) }
    }

    @Test func aSuccessfulFetchIsPlacedAsAnEpisode() async throws {
        let (fetcher, yt, files, store, journal, settings, record) = await rig()
        yt.steps = [.init(result: FakeYtDlp.ok(), sideEffect: writesStaging(files, settings)),
                    .init(result: FakeYtDlp.ok(), sideEffect: writesSubtitles(files, settings, code: "en-j3PyPqV-e1s"))]
        let outcome = await fetcher.fetch(record, subscription: dreamLogic, settings: settings)
        let stem = "\(root)/Shows/Dream Logic/Season 2025/s2025e080501 - When AI Stops Feeling Magical - Greg Hochmuth [snyvQ9COmb8]"
        #expect(outcome == .placed("Shows/Dream Logic/Season 2025/s2025e080501 - When AI Stops Feeling Magical - Greg Hochmuth [snyvQ9COmb8].mp4"))
        #expect(files.files[stem + ".mp4"] != nil)
        #expect(files.files[stem + "-thumb.jpg"] != nil)
        #expect(files.files[stem + ".en.srt"] != nil)
        let nfo = String(decoding: try #require(files.files[stem + ".nfo"]), as: UTF8.self)
        #expect(nfo.contains("<showtitle>Dream Logic</showtitle>"))
        #expect(nfo.contains("<studio>Kirby Ferguson</studio>"))
        let show = String(decoding: try #require(files.files["\(root)/Shows/Dream Logic/tvshow.nfo"]), as: UTF8.self)
        #expect(show.contains("PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj"))
        // Staging is empty and the info.json is not kept.
        #expect(!files.files.keys.contains { $0.contains(".cylindarr/staging") || $0.hasSuffix(".info.json") })
        let saved = try #require(await store.all()["snyvQ9COmb8"])
        #expect(saved.state == .placed)
        #expect(saved.number?.description == "s2025e080501")
        #expect(journal.entries.map(\.verb) == [.fetch, .encode, .describe, .place])
        // What is placed is the encode, and nothing was cut: AAC copied, the
        // source's chapters kept.
        #expect(files.files[stem + ".mp4"] == Data("hevc".utf8))
        let encode = try #require((fetcher.finisher.ffmpeg as! FakeFFmpeg).calls.first)
        #expect(encode.contains("libx265") && !encode.contains("-af"))
        // The fixture video has no SponsorBlock cuts, so the sidecar is moved as is.
        #expect(String(decoding: files.files[stem + ".en.srt"] ?? Data(), as: UTF8.self).contains("00:00:10,000"))
        // Anonymous, with the PO token provider and without cookies; then
        // subtitles from the saved info.json, with no second extraction.
        #expect(yt.calls.count == 2)
        #expect(!yt.calls[0].contains("--cookies"))
        #expect(!yt.calls[0].contains("--write-subs"))
        #expect(yt.calls[1].contains("--load-info-json") && yt.calls[1].contains("--skip-download"))
        #expect(yt.calls[0].contains("youtubepot-bgutilhttp:base_url=http://pot:4416"))
        #expect(yt.calls[0].contains("--sponsorblock-mark"))
        #expect(!yt.calls[0].contains("--sponsorblock-remove"))
    }

    @Test func theBotCheckDefersAndSaysWhen() async throws {
        let (fetcher, yt, _, store, journal, settings, record) = await rig()
        yt.steps = [.init(result: FakeYtDlp.fail(Fixture.text("errors/bot-check.txt")))]
        #expect(await fetcher.fetch(record, subscription: dreamLogic, settings: settings) == .deferred(.botCheck))
        let saved = try #require(await store.all()["snyvQ9COmb8"])
        #expect(saved.state == .deferred(.botCheck, until: now.addingTimeInterval(3600)))
        #expect(saved.attempts == 1)
        #expect(journal.entries.last?.outcome == .deferred)
    }

    @Test func cookiesAreTriedOnceWhenTheyCouldHelp() async throws {
        let (fetcher, yt, files, _, _, settings, record) = await rig(cookies: true)
        yt.steps = [.init(result: FakeYtDlp.fail(Fixture.text("errors/age-gate.txt"))),
                    .init(result: FakeYtDlp.ok(), sideEffect: writesStaging(files, settings)),
                    .init(result: FakeYtDlp.ok())]
        guard case .placed = await fetcher.fetch(record, subscription: dreamLogic, settings: settings) else {
            Issue.record("not placed"); return
        }
        #expect(yt.calls.count == 3)
        #expect(!yt.calls[0].contains("--cookies"))
        #expect(yt.calls[1].contains("--cookies"))
    }

    @Test func anAgeGateWithNoCookiesFailsWithTheReason() async throws {
        let (fetcher, yt, _, store, _, settings, record) = await rig()
        yt.steps = [.init(result: FakeYtDlp.fail(Fixture.text("errors/age-gate.txt")))]
        #expect(await fetcher.fetch(record, subscription: dreamLogic, settings: settings) == .failed(.ageRestricted))
        #expect(await store.all()["snyvQ9COmb8"]?.lastCause?.hasPrefix("no cookies configured") == true)
    }

    @Test func aRemovedVideoFailsAtOnce() async {
        let (fetcher, yt, _, _, _, settings, record) = await rig(cookies: true)
        yt.steps = [.init(result: FakeYtDlp.fail(Fixture.text("errors/unavailable.txt")))]
        #expect(await fetcher.fetch(record, subscription: dreamLogic, settings: settings) == .failed(.removed))
        #expect(yt.calls.count == 1)
    }

    @Test func repeatedUnknownFailuresStopDeferring() async throws {
        let (fetcher, yt, _, store, _, settings, record) = await rig()
        var r = record
        r.attempts = 1
        yt.steps = [.init(result: FakeYtDlp.fail("ERROR: [youtube] snyvQ9COmb8: something new"))]
        #expect(await fetcher.fetch(r, subscription: dreamLogic, settings: settings) == .failed(.gaveUp))
        #expect(await store.all()["snyvQ9COmb8"]?.state == .failed(.gaveUp))
    }

    @Test func ytDlpsDateFilterSkipsWithoutAFailure() async throws {
        let (fetcher, yt, _, store, _, settings, record) = await rig()
        var sub = dreamLogic
        sub.rules.cutoff = Fixture.date("2026-01-01T00:00:00Z")
        yt.steps = [.init(result: .init(exitCode: 0, stdout: Data("[download] 2025-08-05 upload date is not in range 2026-01-01 to 9999-12-31\n".utf8), stderr: ""))]
        #expect(await fetcher.fetch(record, subscription: sub, settings: settings) == .skipped(.beforeCutoff))
        #expect(yt.calls[0].contains("--dateafter"))
        #expect(yt.calls[0][yt.calls[0].firstIndex(of: "--dateafter")! + 1] == "20260101")
        #expect(await store.all()["snyvQ9COmb8"]?.state == .skipped(.beforeCutoff))
    }

    @Test func aFullDiskDefersWithoutRunningYtDlp() async {
        let (fetcher, yt, files, _, _, settings, record) = await rig()
        files.free = 10_000_000_000
        #expect(await fetcher.fetch(record, subscription: dreamLogic, settings: settings) == .deferred(.lowDisk))
        #expect(yt.calls.isEmpty)
    }

    @Test func aShortFoundOnlyAtFetchTimeIsSkippedAndCleanedUp() async throws {
        let (fetcher, yt, files, store, _, settings, record) = await rig()
        yt.steps = [.init(result: FakeYtDlp.ok(), sideEffect: { args in
            self.writesStaging(files, settings)(args)
            let s = settings.staging(for: "snyvQ9COmb8") + "/snyvQ9COmb8.info.json"
            var json = try! JSONSerialization.jsonObject(with: files.files[s]!) as! [String: Any]
            json["media_type"] = "short"
            files.files[s] = try! JSONSerialization.data(withJSONObject: json)
        })]
        #expect(await fetcher.fetch(record, subscription: dreamLogic, settings: settings) == .skipped(.short))
        #expect(files.files.isEmpty)
        #expect(await store.all()["snyvQ9COmb8"]?.state == .skipped(.short))
    }

    @Test func subtitlesAreCutToMatchTheVideo() async throws {
        let (fetcher, yt, files, _, _, settings, record) = await rig()
        yt.steps = [.init(result: FakeYtDlp.ok(), sideEffect: { args in
            self.writesStaging(files, settings)(args)
            let s = settings.staging(for: "snyvQ9COmb8") + "/snyvQ9COmb8.info.json"
            var json = try! JSONSerialization.jsonObject(with: files.files[s]!) as! [String: Any]
            json["sponsorblock_chapters"] = [["start_time": 2.0, "end_time": 6.0, "category": "sponsor"],
                                             ["start_time": 7.0, "end_time": 8.0, "category": "filler"]]
            files.files[s] = try! JSONSerialization.data(withJSONObject: json)
        }), .init(result: FakeYtDlp.ok(), sideEffect: writesSubtitles(files, settings))]
        (fetcher.finisher.ffmpeg as! FakeFFmpeg).played = 261.4
        guard case .placed = await fetcher.fetch(record, subscription: dreamLogic, settings: settings) else { Issue.record("not placed"); return }
        let srt = try #require(files.files.first { $0.key.hasSuffix(".en.srt") }?.value)
        // Only the sponsor segment was cut (filler is not a category here): four seconds earlier.
        #expect(String(decoding: srt, as: UTF8.self).contains("00:00:06,000 --> 00:00:08,000"))
        // And the encode cut the same four seconds.
        let encode = try #require((fetcher.finisher.ffmpeg as! FakeFFmpeg).calls.first)
        let filter = try #require(encode.firstIndex(of: "-af").map { encode[$0 + 1] })
        #expect(filter.hasPrefix("aselect='not(gte(t,2.000)*lt(t,6.000))',asetpts='PTS-(gte(T,6.000)*4.000)/TB'"))
    }

    /// A placed video downloaded again (to re-encode it) keeps its number,
    /// replaces its files, and removes the old ones when its title changed.
    @Test func aPlacedVideoDownloadedAgainReplacesItself() async throws {
        let (fetcher, yt, files, store, _, settings, record) = await rig()
        let oldStem = "Shows/Dream Logic/Season 2025/s2025e080501 - An Older Title [snyvQ9COmb8]"
        files.files["\(root)/\(oldStem).mp4"] = Data("h264".utf8)
        files.files["\(root)/\(oldStem).nfo"] = Data("nfo".utf8)
        files.files["\(root)/\(oldStem)-thumb.jpg"] = Data("jpg".utf8)
        files.files["\(root)/Shows/Dream Logic/Season 2025/s2025e080502 - Another [xxxxxxxxxxx].mp4"] = Data("other".utf8)
        var placed = record
        placed.state = .wanted
        placed.number = EpisodeNumber.parse("s2025e080501")
        placed.path = oldStem + ".mp4"
        yt.steps = [.init(result: FakeYtDlp.ok(), sideEffect: writesStaging(files, settings)), .init(result: FakeYtDlp.ok())]
        let outcome = await fetcher.fetch(placed, subscription: dreamLogic, settings: settings)
        #expect(outcome == .placed("Shows/Dream Logic/Season 2025/s2025e080501 - When AI Stops Feeling Magical - Greg Hochmuth [snyvQ9COmb8].mp4"))
        #expect(!files.files.keys.contains { $0.contains("An Older Title") })
        #expect(files.files.keys.contains { $0.hasSuffix("[xxxxxxxxxxx].mp4") })
        #expect(await store.all()["snyvQ9COmb8"]?.number?.description == "s2025e080501")
    }

    @Test func aFailedSecondDownloadKeepsThePlacedFile() async throws {
        let (fetcher, yt, files, store, _, settings, record) = await rig()
        var placed = record
        placed.path = "Shows/Dream Logic/Season 2025/s2025e080501 - x [snyvQ9COmb8].mp4"
        placed.number = EpisodeNumber.parse("s2025e080501")
        files.files["\(root)/\(placed.path!)"] = Data("h264".utf8)
        yt.steps = [.init(result: FakeYtDlp.ok(), sideEffect: writesStaging(files, settings)), .init(result: FakeYtDlp.ok())]
        (fetcher.finisher.ffmpeg as! FakeFFmpeg).failure = "[hevc_qsv @ 0x1] Error initializing an internal MFX session"
        #expect(await fetcher.fetch(placed, subscription: dreamLogic, settings: settings) == .failed(.unrecognised))
        let saved = try #require(await store.all()["snyvQ9COmb8"])
        #expect(saved.state == .placed)
        #expect(saved.lastCause?.contains("MFX session") == true)
        #expect(files.files["\(root)/\(placed.path!)"] == Data("h264".utf8))
    }

    @Test func aFailedEncodeFailsANewVideo() async throws {
        let (fetcher, yt, files, store, _, settings, record) = await rig()
        yt.steps = [.init(result: FakeYtDlp.ok(), sideEffect: writesStaging(files, settings)), .init(result: FakeYtDlp.ok())]
        (fetcher.finisher.ffmpeg as! FakeFFmpeg).failure = "Conversion failed!"
        #expect(await fetcher.fetch(record, subscription: dreamLogic, settings: settings) == .failed(.unrecognised))
        #expect(await store.all()["snyvQ9COmb8"]?.state == .failed(.unrecognised))
        #expect(files.files.isEmpty)
    }

    /// With encoding off, yt-dlp's file is placed as it came, H.264 first,
    /// and SponsorBlock segments stay in it as chapters.
    @Test func withEncodingOffTheDownloadIsPlacedAsItCame() async throws {
        var (fetcher, yt, files, _, journal, settings, record) = await rig()
        settings.encode = EncodeSettings(encoder: .none)
        yt.steps = [.init(result: FakeYtDlp.ok(), sideEffect: { args in
            self.writesStaging(files, settings)(args)
            let s = settings.staging(for: "snyvQ9COmb8") + "/snyvQ9COmb8.info.json"
            var json = try! JSONSerialization.jsonObject(with: files.files[s]!) as! [String: Any]
            json["sponsorblock_chapters"] = [["start_time": 2.0, "end_time": 6.0, "category": "sponsor"]]
            files.files[s] = try! JSONSerialization.data(withJSONObject: json)
        }), .init(result: FakeYtDlp.ok(), sideEffect: writesSubtitles(files, settings))]
        guard case .placed(let path) = await fetcher.fetch(record, subscription: dreamLogic, settings: settings) else { Issue.record("not placed"); return }
        #expect(files.files["\(root)/\(path)"] == Data("video".utf8))
        #expect((fetcher.finisher.ffmpeg as! FakeFFmpeg).calls.isEmpty)
        #expect(!journal.entries.contains { $0.verb == .encode })
        let srt = try #require(files.files.first { $0.key.hasSuffix(".en.srt") }?.value)
        #expect(String(decoding: srt, as: UTF8.self).contains("00:00:10,000 --> 00:00:12,000"))
        let format = try #require(yt.calls[0].firstIndex(of: "-f").map { yt.calls[0][$0 + 1] })
        #expect(format.hasPrefix("bv*[height<=1080][dynamic_range=?SDR][protocol^=http][vcodec^=avc1]+ba[acodec^=mp4a]/"))
        #expect(yt.calls[0].contains("--sponsorblock-mark"))
    }

    /// Intel graphics older than Ice Lake have no low-power HEVC encoder;
    /// the encode is tried again in Quick Sync's default mode.
    @Test func quickSyncFallsBackFromLowPower() async throws {
        var (fetcher, yt, files, _, journal, settings, record) = await rig()
        settings.encode = EncodeSettings(encoder: .quickSync(device: "/dev/dri/renderD128"))
        let ffmpeg = fetcher.finisher.ffmpeg as! FakeFFmpeg
        ffmpeg.failure = "[hevc_qsv @ 0x1] Error initializing the encoder: unsupported (-3)"
        ffmpeg.failWhen = "-low_power"
        yt.steps = [.init(result: FakeYtDlp.ok(), sideEffect: writesStaging(files, settings)), .init(result: FakeYtDlp.ok())]
        guard case .placed = await fetcher.fetch(record, subscription: dreamLogic, settings: settings) else { Issue.record("not placed"); return }
        #expect(ffmpeg.calls.count == 2)
        #expect(ffmpeg.calls[0].contains("-low_power") && !ffmpeg.calls[1].contains("-low_power"))
        #expect(journal.entries.contains { $0.verb == .encode && $0.outcome == .ok && $0.detail.hasPrefix("HEVC with Quick Sync") })
    }

    /// An encode that stopped short is not placed, and not placed over a
    /// file already there.
    @Test func anEncodeOfTheWrongLengthIsNotPlaced() async throws {
        let (fetcher, yt, files, store, journal, settings, record) = await rig()
        var placed = record
        placed.path = "Shows/Dream Logic/Season 2025/s2025e080501 - x [snyvQ9COmb8].mp4"
        placed.number = EpisodeNumber.parse("s2025e080501")
        files.files["\(root)/\(placed.path!)"] = Data("h264".utf8)
        yt.steps = [.init(result: FakeYtDlp.ok(), sideEffect: writesStaging(files, settings)), .init(result: FakeYtDlp.ok())]
        (fetcher.finisher.ffmpeg as! FakeFFmpeg).played = 600
        #expect(await fetcher.fetch(placed, subscription: dreamLogic, settings: settings) == .failed(.unrecognised))
        #expect(files.files["\(root)/\(placed.path!)"] == Data("h264".utf8))
        #expect(await store.all()["snyvQ9COmb8"]?.state == .placed)
        #expect(journal.entries.contains { $0.verb == .encode && $0.detail == "the encode plays for 600.0 s, not 265.0 s" })
    }

    @Test func aGrabListVideoBecomesAFilm() async throws {
        var grabs = dreamLogic
        grabs.isGrabList = true
        let (fetcher, yt, files, _, _, settings, record) = await rig()
        yt.steps = [.init(result: FakeYtDlp.ok(), sideEffect: writesStaging(files, settings))]
        let outcome = await fetcher.fetch(record, subscription: grabs, settings: settings)
        #expect(outcome == .placed("Grabs/When AI Stops Feeling Magical - Greg Hochmuth (2025) [snyvQ9COmb8]/When AI Stops Feeling Magical - Greg Hochmuth (2025) [snyvQ9COmb8].mp4"))
        #expect(files.files.keys.contains { $0.hasSuffix("[snyvQ9COmb8]/poster.jpg") })
        #expect(!files.files.keys.contains { $0.hasSuffix("tvshow.nfo") })
    }
}

@Suite struct QueueGateTests {
    let t = Fixture.date("2026-09-27T12:00:00Z")

    @Test func threeBotChecksInARowPauseEverything() {
        var gate = QueueGate()
        gate.record(.deferred(.botCheck), at: t)
        gate.record(.deferred(.botCheck), at: t)
        #expect(gate.isOpen(at: t))
        gate.record(.deferred(.botCheck), at: t)
        #expect(!gate.isOpen(at: t))
        #expect(gate.reason == .botCheck)
        #expect(gate.isOpen(at: t.addingTimeInterval(3601)))
    }

    @Test func aSuccessResetsTheCount() {
        var gate = QueueGate()
        gate.record(.deferred(.botCheck), at: t)
        gate.record(.deferred(.botCheck), at: t)
        gate.record(.placed("x"), at: t)
        gate.record(.deferred(.botCheck), at: t)
        #expect(gate.isOpen(at: t))
        #expect(gate.consecutiveBotChecks == 1)
    }

    @Test func aFullDiskPausesAtOnce() {
        var gate = QueueGate()
        gate.record(.deferred(.lowDisk), at: t)
        #expect(!gate.isOpen(at: t))
    }
}
