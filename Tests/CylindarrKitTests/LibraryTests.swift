import Foundation
import Testing
@testable import CylindarrKit

@Suite struct EpisodeNumberingTests {
    /// Three videos from one channel on 2017-07-18, all `s2017e0718` in Pinchflat.
    @Test func sameDayUploadsNeverCollide() {
        let uploads = [
            EpisodeNumbering.Upload(id: "ccccccccccc", uploaded: Fixture.date("2017-07-18T12:00:00Z")),
            EpisodeNumbering.Upload(id: "aaaaaaaaaaa", uploaded: Fixture.date("2017-07-18T12:00:00Z")),
            EpisodeNumbering.Upload(id: "bbbbbbbbbbb", uploaded: Fixture.date("2017-07-18T09:00:00Z")),
        ]
        let n = EpisodeNumbering.assign(uploads, taken: [])
        #expect(n["bbbbbbbbbbb"]?.description == "s2017e071801")
        #expect(n["aaaaaaaaaaa"]?.description == "s2017e071802")
        #expect(n["ccccccccccc"]?.description == "s2017e071803")
    }

    /// Adding back catalogue never renumbers what is already placed.
    @Test func olderArrivalsTakeTheNextFreeIndex() {
        let taken: Set = [EpisodeNumber(season: 2017, episode: 71801)]
        let n = EpisodeNumbering.assign([.init(id: "early", uploaded: Fixture.date("2017-07-18T01:00:00Z"))], taken: taken)
        #expect(n["early"]?.description == "s2017e071802")
    }

    @Test func daysAreUTC() {
        // 23:30 in New York on the 23rd is the 24th at YouTube.
        let n = EpisodeNumbering.assign([.init(id: "x", uploaded: Fixture.date("2026-09-24T03:30:00Z"))], taken: [])
        #expect(n["x"]?.description == "s2026e092401")
    }

    @Test func numbersReadBack() {
        #expect(EpisodeNumber.parse("s2017e071802") == EpisodeNumber(season: 2017, episode: 71802))
        // Pinchflat's scheme, read as index 0 so adoption knows it.
        #expect(EpisodeNumber.parse("s2017e0718") == EpisodeNumber(season: 2017, episode: 71800))
        #expect(EpisodeNumber.parse("S2017E071802 - Title") == EpisodeNumber(season: 2017, episode: 71802))
        #expect(EpisodeNumber.parse("2017-07-18") == nil)
        #expect(EpisodeNumber(season: 2017, episode: 71802).month == 7)
        #expect(EpisodeNumber(season: 2017, episode: 71802).day == 18)
    }
}

@Suite struct NamingTests {
    @Test func pinchflatsLookalikesAreUndone() {
        #expect(PathSafety.clean("When China Failed to Conquer Taiwan： the Battle for Kinmen Island") ==
                "When China Failed to Conquer Taiwan - the Battle for Kinmen Island")
        #expect(PathSafety.clean("Who Will Join China's Most Powerful Body？ The 19th Party Congress") ==
                "Who Will Join China's Most Powerful Body The 19th Party Congress")
    }

    @Test func pathCharacters() {
        #expect(PathSafety.clean("AC/DC: Live | 1991") == "AC-DC - Live 1991")
        #expect(PathSafety.clean("...") == "Untitled")
        #expect(PathSafety.clean("  Tabs\tand\nnewlines  ") == "Tabs and newlines")
        #expect(PathSafety.clean("Post Malone 🤟🍻 Full Set") == "Post Malone 🤟🍻 Full Set")
        #expect(PathSafety.clean("臺北 101") == "臺北 101")
    }

    @Test func truncationRespectsBytesAndCharacters() {
        let long = String(repeating: "臺北 ", count: 100)
        let cut = PathSafety.truncate(long, toBytes: 50)
        #expect(cut.utf8.count <= 50)
        #expect(!cut.hasSuffix(" "))
        #expect(PathSafety.truncate("short", toBytes: 50) == "short")
    }

    @Test func anEpisodesFiles() {
        let n = EpisodeNumber(season: 2026, episode: 92401)
        let p = NamingScheme.episode(show: "Technology Connections", number: n,
                                     title: "Engines haven't been fully mechanical in decades - and that's good!", videoID: "0KoeY54M5VA")
        #expect(p.directory == "Shows/Technology Connections/Season 2026")
        #expect(p.media == "Shows/Technology Connections/Season 2026/s2026e092401 - Engines haven't been fully mechanical in decades - and that's good! [0KoeY54M5VA].mp4")
        #expect(p.nfo.hasSuffix("[0KoeY54M5VA].nfo"))
        #expect(p.thumbnail.hasSuffix("[0KoeY54M5VA]-thumb.jpg"))
        #expect(p.subtitle("en").hasSuffix("[0KoeY54M5VA].en.srt"))
    }

    @Test func everyNameFitsTheBudget() {
        let title = String(repeating: "A very long title about semiconductors ", count: 20)
        let p = NamingScheme.episode(show: "Asianometry", number: EpisodeNumber(season: 2019, episode: 32501), title: title, videoID: "3nTpW52nioI")
        for path in [p.media, p.nfo, p.thumbnail, p.subtitle("en-GB")] {
            #expect((path as NSString).lastPathComponent.utf8.count <= NamingScheme.maxNameBytes)
            #expect(NamingScheme.videoID(inFileName: (path as NSString).lastPathComponent) == "3nTpW52nioI")
        }
    }

    @Test func aGrab() {
        let p = NamingScheme.grab(title: "How to Speak", year: 2019, videoID: "Unzc731iCUY")
        #expect(p.media == "Grabs/How to Speak (2019) [Unzc731iCUY]/How to Speak (2019) [Unzc731iCUY].mp4")
        #expect(p.thumbnail == "Grabs/How to Speak (2019) [Unzc731iCUY]/poster.jpg")
    }

    @Test func theIDInANameIsTheLastBracketedID() {
        #expect(NamingScheme.videoID(inFileName: "Song [Live] [dQw4w9WgXcQ].mp4") == "dQw4w9WgXcQ")
        #expect(NamingScheme.videoID(inFileName: "s2017e0718 - Title.mp4") == nil)
    }
}

@Suite struct NFOTests {
    @Test func theShowTitleIsTheSubscriptionsNotTheUploaders() {
        let nfo = NFOWriter.episode(.init(
            title: "Everything is a Remix Part 1", showTitle: "Everything is a Remix",
            number: EpisodeNumber(season: 2010, episode: 91401), aired: Fixture.date("2010-09-14T12:00:00Z"),
            plot: "Part 1 of 4 & more <links>", runtimeSeconds: 460, studio: "Kirby Ferguson", videoID: "nJPERZDfyWc",
            thumb: "x-thumb.jpg", sponsorBlockCuts: 2))
        #expect(nfo.contains("<showtitle>Everything is a Remix</showtitle>"))
        #expect(nfo.contains("<studio>Kirby Ferguson</studio>"))
        #expect(nfo.contains("<season>2010</season>"))
        #expect(nfo.contains("<episode>91401</episode>"))
        #expect(nfo.contains("<aired>2010-09-14</aired>"))
        #expect(nfo.contains("<runtime>8</runtime>"))
        #expect(nfo.contains("Part 1 of 4 &amp; more &lt;links&gt;"))
        #expect(nfo.contains("2 SponsorBlock segments cut."))
        #expect(nfo.contains(#"<uniqueid type="youtube" default="true">nJPERZDfyWc</uniqueid>"#))
    }

    @Test func controlCharactersAreDropped() {
        #expect(NFOWriter.escape("a\u{0B}b\u{1}c\nd") == "abc\nd")
    }

    @Test func aShowAndAMovie() {
        let show = NFOWriter.tvshow(.init(title: "Dream Logic", plot: "Kirby Ferguson's series", studio: "Kirby Ferguson",
                                          youtubeID: "PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj"))
        #expect(show.contains("<title>Dream Logic</title>"))
        #expect(show.contains("PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj"))
        let movie = NFOWriter.movie(.init(title: "How to Speak", premiered: Fixture.date("2019-12-20T12:00:00Z"), videoID: "Unzc731iCUY"))
        #expect(movie.contains("<year>2019</year>"))
        #expect(movie.hasPrefix(#"<?xml version="1.0""#))
    }
}
