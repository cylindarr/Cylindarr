import Foundation
import Testing
@testable import CylindarrKit

@Suite struct AdopterTests {
    static let tree = Fixture.text("trees/pinchflat.txt").split(separator: "\n").map(String.init)

    /// A Pinchflat tree with the quirks of a real one: every sidecar kind,
    /// full-width look-alikes in titles, a show's own poster and NFO, and
    /// what an interrupted download leaves (see trees/make-trees.py).
    @Test func aPinchflatTreeGroupsIntoItsVideos() {
        let (groups, loose, debris) = Adopter.group(Self.tree)
        #expect(groups.count == 76)
        #expect(groups.allSatisfy { $0.media != nil })
        #expect(groups.allSatisfy { $0.sidecars.values.contains(.infoJSON) })
        #expect(groups.allSatisfy { EpisodeNumber.parse(Substring($0.stem)) != nil })
        #expect(loose == ["shows/Quiet Machines/poster.jpg", "shows/Quiet Machines/tvshow.nfo"])
        #expect(debris == [
            "shows/Old Archive/s2016e0517 - The Archive (Original Series).en.temp.srt.concat",
            "shows/Old Archive/s2016e0517 - The Archive (Original Series).temp.mp4",
        ])
    }

    @Test func pinchflatsSidecarsAreRecognised() throws {
        let (groups, _, _) = Adopter.group(Self.tree)
        let g = try #require(groups.first { $0.stem.hasPrefix("s2017e0718 - Reading the Harbour Master") })
        #expect(Set(g.sidecars.values) == [.infoJSON, .nfo, .thumbnail, .subtitle])
        #expect(g.idInName == nil)
    }

    static let threeOnOneDay = [
        ("s2017e0718 - Reading the Harbour Master's Log", "AAAAAAAAAA1", "Reading the Harbour Master's Log", "2017-07-18T09:00:00Z"),
        ("s2017e0718 - Visiting the Lighthouse at Night, in 4K", "AAAAAAAAAA2", "Visiting the Lighthouse at Night, in 4K", "2017-07-18T12:00:00Z"),
        ("s2017e0718 - Who Keeps the Lights On？ The Keepers' Union", "AAAAAAAAAA3", "Who Keeps the Lights On？ The Keepers' Union", "2017-07-18T12:00:00Z"),
    ]

    func harbourPlan() -> Adopter.Plan {
        let paths = Self.tree.filter { $0.contains("s2017e0718") || $0.contains("Grab List/") || $0.hasPrefix("shows/Old Archive/") }
        let (groups, _, _) = Adopter.group(paths)
        var facts: [String: Adopter.Facts] = [:]
        for (stem, id, title, when) in Self.threeOnOneDay {
            facts["shows/Harbour Lights/" + stem] = .init(id: id, title: title, uploaded: Fixture.date(when), uploader: "Harbour Lights")
        }
        facts["shows/Grab List/s2019e1220 - A Lecture on Speaking"] =
            .init(id: "BBBBBBBBBB1", title: "A Lecture on Speaking", uploaded: Fixture.date("2019-12-20T12:00:00Z"), uploader: "A University")
        return Adopter.plan(
            groups: groups, facts: facts,
            destinations: ["shows/Harbour Lights": .show("Harbour Lights"), "shows/Grab List": .grabs],
            sourcePrefix: "/old/pinchflat", libraryPrefix: "/data/youtube")
    }

    @Test func threeVideosOnOneDayGetThreeNumbers() {
        let plan = harbourPlan()
        let numbers = plan.placed.compactMap(\.number).map(\.description)
        #expect(numbers == ["s2017e071801", "s2017e071802", "s2017e071803"])
        #expect(plan.placed.contains { $0.media == "Shows/Harbour Lights/Season 2017/s2017e071803 - Who Keeps the Lights On The Keepers' Union [AAAAAAAAAA3].mp4" })
    }

    @Test func aGrabListVideoBecomesAFilm() throws {
        let plan = harbourPlan()
        let grab = try #require(plan.placed.first { $0.id == "BBBBBBBBBB1" })
        #expect(grab.destination == .grabs)
        #expect(grab.media == "Grabs/A Lecture on Speaking (2019) [BBBBBBBBBB1]/A Lecture on Speaking (2019) [BBBBBBBBBB1].mp4")
        #expect(plan.operations.contains(.move(
            from: "/old/pinchflat/shows/Grab List/s2019e1220 - A Lecture on Speaking-thumb.jpg",
            to: "/data/youtube/Grabs/A Lecture on Speaking (2019) [BBBBBBBBBB1]/poster.jpg")))
    }

    @Test func theOldNFOAndInfoJSONAreReplaced() {
        let plan = harbourPlan()
        let old = "/old/pinchflat/shows/Harbour Lights/s2017e0718 - Visiting the Lighthouse at Night, in 4K"
        #expect(plan.operations.contains(.remove(old + ".info.json")))
        #expect(plan.operations.contains(.remove(old + ".nfo")))
        let writes = plan.operations.compactMap { if case .write(let p, let c) = $0 { (p, c) } else { nil } }
        let nfo = writes.first { $0.0.contains("AAAAAAAAAA2") }
        #expect(nfo?.0 == "/data/youtube/Shows/Harbour Lights/Season 2017/s2017e071802 - Visiting the Lighthouse at Night, in 4K [AAAAAAAAAA2].nfo")
        #expect(nfo?.1.contains("<showtitle>Harbour Lights</showtitle>") == true)
    }

    /// Unmapped folders and unidentified videos are listed, never guessed.
    @Test func whatCannotBePlacedIsListed() {
        let plan = harbourPlan()
        // In a folder mapped to Grabs, a video with no facts is filed by name, not left.
        #expect(plan.placedByName.contains { $0.hasSuffix("s2009e1110 - A Full Lecture on Sleep (Complete).mp4") })
        #expect(plan.problems.contains { $0.kind == .unidentified && $0.path.contains("Old Archive") })
        let mapped = Adopter.plan(groups: Adopter.group(["x/y/a [dQw4w9WgXcQ].mp4"]).groups,
                                  facts: ["x/y/a [dQw4w9WgXcQ]": .init(id: "dQw4w9WgXcQ", title: "a", uploaded: Date())],
                                  destinations: [:], sourcePrefix: "/s", libraryPrefix: "/l")
        #expect(mapped.problems == [.init(kind: .unmappedFolder, path: "x/y")])
    }

    @Test func aVideoAlreadyPlacedIsNotPlacedTwice() {
        let g = Adopter.group(["a/v [dQw4w9WgXcQ].mp4"]).groups
        let plan = Adopter.plan(groups: g, facts: ["a/v [dQw4w9WgXcQ]": .init(id: "dQw4w9WgXcQ", title: "v", uploaded: Date())],
                                destinations: ["a": .show("A")], alreadyPlaced: ["dQw4w9WgXcQ"], sourcePrefix: "/s", libraryPrefix: "/l")
        #expect(plan.placed.isEmpty)
        #expect(plan.problems.first?.kind == .duplicate)
    }

    @Test func anExistingShowsNumbersAreRespected() {
        let g = Adopter.group(["a/v [dQw4w9WgXcQ].mp4"]).groups
        let plan = Adopter.plan(groups: g, facts: ["a/v [dQw4w9WgXcQ]": .init(id: "dQw4w9WgXcQ", title: "v", uploaded: Fixture.date("2020-01-02T00:00:00Z"))],
                                destinations: ["a": .show("A")], taken: ["A": [EpisodeNumber(season: 2020, episode: 10201)]],
                                sourcePrefix: "/s", libraryPrefix: "/l")
        #expect(plan.placed.first?.number?.description == "s2020e010202")
    }
}

@Suite struct CookieJarTests {
    static let good = """
    # Netscape HTTP Cookie File
    .youtube.com\tTRUE\t/\tTRUE\t1822000000\tSAPISID\tx
    .youtube.com\tTRUE\t/\tTRUE\t1822000000\t__Secure-3PSID\tx
    #HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t1810000000\tLOGIN_INFO\tx
    .youtube.com\tTRUE\t/\tFALSE\t0\tPREF\tx
    """

    @Test func aSignedInJarHasNoProblems() {
        let jar = CookieJar.parse(Self.good)
        #expect(jar.cookies.count == 4)
        #expect(jar.problems(at: Date(timeIntervalSince1970: 1790000000)).isEmpty)
        #expect(jar.earliestRequiredExpiry == Date(timeIntervalSince1970: 1810000000))
    }

    @Test func anAnonymousJarSaysWhatIsMissing() {
        let jar = CookieJar.parse(".youtube.com\tTRUE\t/\tFALSE\t0\tPREF\tx\n")
        #expect(jar.problems(at: Date()) == [.missing(CookieJar.requiredNames)])
    }

    @Test func anExpiredSessionIsCaught() {
        let jar = CookieJar.parse(Self.good)
        #expect(jar.problems(at: Date(timeIntervalSince1970: 1815000000)) == [.expired("LOGIN_INFO", Date(timeIntervalSince1970: 1810000000))])
    }

    @Test func notACookieFile() {
        #expect(CookieJar.parse("{\"json\": true}").problems(at: Date()) == [.notNetscapeFormat])
        #expect(CookieJar.parse(".example.com\tTRUE\t/\tFALSE\t0\ta\tb").problems(at: Date()) == [.noYouTubeCookies])
    }

    @Test func onlyYouTubeAndGoogleAreKept() {
        let export = Self.good + """

        .bank.example\tTRUE\t/\tTRUE\t1822000000\tsession\tsecret
        #HttpOnly_.accounts.google.com\tTRUE\t/\tTRUE\t1822000000\tSID\tx
        # a comment
        """
        let kept = CookieJar.youtubeOnly(export)
        #expect(!kept.contains("bank"))
        #expect(!kept.contains("a comment"))
        #expect(kept.hasPrefix("# Netscape HTTP Cookie File\n"))
        let jar = CookieJar.parse(kept)
        #expect(jar.cookies.count == 5)
        #expect(jar.cookies.map(\.name).contains("LOGIN_INFO"))
        #expect(jar.problems(at: Date(timeIntervalSince1970: 1790000000)).isEmpty)
    }
}

@Suite struct JournalTests {
    @Test func cookiesNeverReachTheLog() {
        let e = Entry(verb: .fetch, noun: .video, subject: "x", outcome: .deferred,
                      detail: "yt-dlp --cookies /app/data/cookies.txt -f best URL",
                      data: ["cookies": "/app/data/cookies.txt", "url": "http://plex:32400/x?X-Plex-Token=abc&y=1"])
        #expect(e.detail == "yt-dlp --cookies <redacted> -f best URL")
        #expect(e.data["cookies"] == "<redacted>")
        #expect(e.data["url"] == "http://plex:32400/x?X-Plex-Token=<redacted>&y=1")
    }

    @Test func passwordsInURLsNeverReachTheLog() {
        let e = Entry(verb: .configure, noun: .system, subject: "startup", outcome: .ok,
                      detail: "proxy=socks5://cylindarr:hunter2@proxy.example:1080 pot=http://pot:4416")
        #expect(e.detail == "proxy=socks5://cylindarr:<redacted>@proxy.example:1080 pot=http://pot:4416")
        #expect(Entry(verb: .fetch, noun: .video, subject: "x", outcome: .ok, data: ["p": "socks5://u:p@h:1"]).data["p"] == "socks5://u:<redacted>@h:1")
    }

    @Test func theLineHasFixedColumns() {
        let e = Entry(verb: .poll, noun: .subscription, subject: "Technology Connections", outcome: .ok, detail: "1 new")
        #expect(e.line.contains("poll      subscription \"Technology Connections\""))
        #expect(e.line.hasSuffix("ok       1 new"))
    }
}

@Suite struct TubeSyncAdoptionTests {
    static let tree = Fixture.text("trees/tubesync.txt").split(separator: "\n").map(String.init)

    @Test func tubeSyncNamesCarryTheirIDs() {
        #expect(Adopter.videoID(inName: "2016-01-27_paper-lanterns_how-i-write-my-notes-and-drafts_Vr5Nq2Lw8Kz_1080p-vp09-mp4a") == "Vr5Nq2Lw8Kz")
        #expect(Adopter.videoID(inName: "2024-03-15_paper-lanterns_beat-the-blank-page_7Rb_kLp2Wd0_1080p-vp09-mp4a") == "7Rb_kLp2Wd0")
        #expect(Adopter.videoID(inName: "2023-03-21_paper-lanterns_lanterns-complete-updated-2023-edition_Zc9XyT3nQeA_premium-vp09-mp4a") == "Zc9XyT3nQeA")
        #expect(Adopter.videoID(inName: "2014-01-24_paper-lanterns_episode-one-premise_-aB3dE5fG7h_1080p-avc1-mp4a") == "-aB3dE5fG7h")
        #expect(Adopter.videoID(inName: "Conference_Keynote_2021") == nil)
        #expect(Adopter.videoID(inName: "Song [dQw4w9WgXcQ]") == "dQw4w9WgXcQ")
    }

    @Test func aChannelArchiveIsIdentifiedByName() {
        let (groups, _, _) = Adopter.group(Self.tree)
        let channel = groups.filter { $0.folder == "video/Paper Lanterns" && $0.media != nil }
        #expect(channel.count == 9)
        #expect(channel.allSatisfy { $0.idInName != nil })
        // The loose one-offs at the top have no id at all.
        #expect(groups.filter { $0.folder == "" && $0.media != nil }.allSatisfy { $0.idInName == nil })
    }

    @Test func tubeSyncsNFOIsRead() throws {
        let xml = """
        <?xml version='1.0' encoding='utf8'?>
        <episodedetails>
          <title>The First Short</title>
          <showtitle>Paper Lanterns</showtitle>
          <plot>A short film made in a park &amp; more</plot>
          <runtime>97</runtime>
          <id>Qm4TzH8vK2a</id>
          <uniqueid type="youtube" default="True">Qm4TzH8vK2a</uniqueid>
          <studio>Paper Lanterns</studio>
          <aired>2010-04-20</aired>
        </episodedetails>
        """
        let f = try #require(NFOReader.facts(xml))
        #expect(f.id == "Qm4TzH8vK2a" && f.title == "The First Short" && f.uploader == "Paper Lanterns")
        #expect(f.uploaded == Fixture.date("2010-04-20T12:00:00Z"))
        #expect(f.description == "A short film made in a park & more")
    }

    @Test func pinchflatsNFOIsRead() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
        <episodedetails>
          <title>The Harbour Master: A Life at the Light</title>
          <showtitle>Harbour Lights</showtitle>
          <uniqueid type="youtube" default="true">Hq_2WxLp9Za</uniqueid>
          <plot>A life at the light</plot>
          <aired>2017-05-10 00:00:00Z</aired>
          <season>2017</season>
          <episode>0510</episode>
        """
        let f = try #require(NFOReader.facts(xml + "</episodedetails>"))
        #expect(f.id == "Hq_2WxLp9Za")
        #expect(f.uploaded == Fixture.date("2017-05-10T12:00:00Z"))
    }

    @Test func unidentifiedOneOffsMappedToGrabsAreFiledByName() {
        let (groups, _, _) = Adopter.group(Self.tree.filter { !$0.contains("/") })
        let plan = Adopter.plan(groups: groups, facts: [:], destinations: ["": .grabs], sourcePrefix: "/old/tubesync", libraryPrefix: "/l")
        #expect(plan.problems.isEmpty)
        #expect(plan.placedByName.contains("Grabs/Conference Keynote 2021/Conference Keynote 2021.mp4"))
        #expect(plan.placedByName.count == groups.count)
    }

    @Test func vttSubtitlesKeepTheirExtension() {
        let stem = "video/Paper Lanterns/2020-06-30_paper-lanterns_lanterns-reality_Kt3Wq8Zp1Ma_1080p-vp09-mp4a"
        let g = Adopter.group([stem + ".mkv", stem + ".en.vtt", stem + ".nfo"]).groups
        let plan = Adopter.plan(groups: g, facts: [stem: .init(id: "Kt3Wq8Zp1Ma", title: "Lanterns: Reality", uploaded: Fixture.date("2020-06-30T12:00:00Z"))],
                                destinations: ["video/Paper Lanterns": .show("Paper Lanterns")], sourcePrefix: "/s", libraryPrefix: "/l")
        #expect(plan.batches.count == 1)
        #expect(plan.operations.contains(.move(from: "/s/\(stem).mkv", to: "/l/Shows/Paper Lanterns/Season 2020/s2020e063001 - Lanterns - Reality [Kt3Wq8Zp1Ma].mkv")))
        #expect(plan.operations.contains(.move(from: "/s/\(stem).en.vtt", to: "/l/Shows/Paper Lanterns/Season 2020/s2020e063001 - Lanterns - Reality [Kt3Wq8Zp1Ma].en.vtt")))
        #expect(plan.operations.first == .move(from: "/s/\(stem).mkv", to: "/l/Shows/Paper Lanterns/Season 2020/s2020e063001 - Lanterns - Reality [Kt3Wq8Zp1Ma].mkv"))
    }
}
