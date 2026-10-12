import Foundation
import Testing
@testable import CylindarrKit

@Suite struct VideoKeyTests {
    @Test func youTubeKeepsItsBareID() {
        #expect(VideoKey.make(extractor: "Youtube", id: "snyvQ9COmb8") == "snyvQ9COmb8")
        #expect(VideoKey.isYouTube("snyvQ9COmb8"))
    }

    @Test func anotherSiteIsPrefixedWithItsExtractor() {
        let key = VideoKey.make(extractor: "PeerTube", id: "9c9de5e8-0a1e-484a-b099-e80766180a6d")
        #expect(key == "peertube.9c9de5e8-0a1e-484a-b099-e80766180a6d")
        #expect(!VideoKey.isYouTube(key))
        #expect(VideoKey.parts(key) == ("peertube", "9c9de5e8-0a1e-484a-b099-e80766180a6d"))
        #expect(VideoKey.isKey(key))
    }

    /// Eleven characters with only id characters in them would pass for a
    /// YouTube id; the dot is what keeps a short site key from doing so.
    @Test func aShortSiteKeyIsNotTakenForYouTube() {
        let key = VideoKey.make(extractor: "Vimeo", id: "12345")
        #expect(key == "vimeo.12345")
        #expect(key.count == 11)
        #expect(!VideoKey.isYouTube(key))
    }

    @Test func charactersAPathCannotHoldAreReplaced() {
        #expect(VideoKey.make(extractor: "Generic", id: "a/b c%d") == "generic.a_b_c_d")
    }

    @Test func theKeyIsReadBackFromAFileName() {
        #expect(NamingScheme.videoID(inFileName: "What is PeerTube (2018) [peertube.9c9de5e8-0a1e].mp4") == "peertube.9c9de5e8-0a1e")
        #expect(NamingScheme.videoID(inFileName: "s2025e080501 - x [snyvQ9COmb8].mp4") == "snyvQ9COmb8")
        #expect(NamingScheme.videoID(inFileName: "Concert [v1.2].mp4") == nil)
    }

    @Test func aFilmFromAnotherSiteNamesItsSiteInTheNFO() {
        let nfo = NFOWriter.movie(.init(title: "What is PeerTube?", videoID: "peertube.9c9de5e8"))
        #expect(nfo.contains(#"<uniqueid type="peertube" default="true">9c9de5e8</uniqueid>"#))
        let yt = NFOWriter.movie(.init(title: "x", videoID: "snyvQ9COmb8"))
        #expect(yt.contains(#"<uniqueid type="youtube" default="true">snyvQ9COmb8</uniqueid>"#))
    }
}

@Suite struct ResolveTests {
    @Test func aPeerTubeVideoResolvesToItsKey() {
        let d = Resolve.decide(FakeYtDlp.ok(Fixture.data("sites/peertube-video.json")))
        #expect(d == .resolved(key: "peertube.9c9de5e8-0a1e-484a-b099-e80766180a6d", title: "What is PeerTube?",
                               uploaded: Date(timeIntervalSince1970: 1_538_391_166)))
    }

    @Test func audioOnlyIsRefused() {
        guard case .failed(.notVideo, _) = Resolve.decide(FakeYtDlp.ok(Fixture.data("sites/soundcloud-track.json"))) else {
            Issue.record("a SoundCloud track was not refused as audio only"); return
        }
    }

    @Test func aChannelOnAnotherSiteIsRefused() {
        guard case .failed(.notOneVideo, _) = Resolve.decide(FakeYtDlp.ok(Fixture.data("sites/vimeo-channel.json"))) else {
            Issue.record("a Vimeo channel was not refused"); return
        }
    }

    @Test(arguments: [
        ("errors/vimeo-sign-in.txt", FailCause.needsSignIn),
        ("errors/unsupported-url.txt", .unsupported),
        ("errors/peertube-not-found.txt", .removed),
    ])
    func whatYtDlpSaysDecidesTheCause(file: String, cause: FailCause) {
        guard case .failed(let got, _) = Resolve.decide(FakeYtDlp.fail(Fixture.text(file))) else {
            Issue.record("\(file) was not a failure"); return
        }
        #expect(got == cause)
    }

    @Test func theYouTubeBotCheckIsStillABotCheck() {
        #expect(FailureClassifier.diagnose(stderr: Fixture.text("errors/bot-check.txt")) == .deferred(.botCheck))
    }

    @Test func theProxyIsUsedWhenThereIsOne() {
        let a = Resolve.arguments(url: "https://framatube.org/w/x", proxy: "socks5://proxy.example:1080")
        #expect(a.contains("--proxy") && a.last == "https://framatube.org/w/x")
        #expect(!Resolve.arguments(url: "https://x", proxy: nil).contains("--proxy"))
    }
}

@Suite struct SiteFetchTests {
    let settings = FetchSettings(libraryRoot: "/library", cookiesPath: "/data/cookies.txt", potProvider: "http://pot:4416")

    @Test func anotherSiteGetsNoneOfYouTubesArguments() {
        let a = FetchArguments.build(videoID: "peertube.abc", sourceURL: "https://framatube.org/w/abc", rules: Rules(),
                                     settings: settings, withCookies: true)
        #expect(a.last == "https://framatube.org/w/abc")
        #expect(!a.contains("--sponsorblock-mark"))
        #expect(!a.contains("--cookies"))
        #expect(!a.contains { $0.contains("youtubepot") })
        #expect(a.contains("peertube.abc.%(ext)s"))
    }

    @Test func youTubeStillGetsThem() {
        let a = FetchArguments.build(videoID: "snyvQ9COmb8", rules: Rules(), settings: settings, withCookies: true)
        #expect(a.last == "https://www.youtube.com/watch?v=snyvQ9COmb8")
        #expect(a.contains("--sponsorblock-mark") && a.contains("--cookies"))
        #expect(a.contains("snyvQ9COmb8.%(ext)s"))
    }
}
