import Foundation
import Testing
@testable import CylindarrKit

@Suite struct VerifierTests {
    func settings(cookies: Bool = false, pot: Bool = true) -> FetchSettings {
        FetchSettings(libraryRoot: "/l", cookiesPath: cookies ? "/app/data/cookies.txt" : nil,
                      proxy: "socks5://u:p@proxy.example:1080", potProvider: pot ? "http://pot:4416" : nil)
    }

    @Test func aWorkingPathPasses() async {
        let yt = FakeYtDlp()
        yt.steps = [.init(result: FakeYtDlp.ok(Data("2026.08.19\n".utf8))), .init(result: FakeYtDlp.ok())]
        let feeds = FakeFeeds()
        feeds.responses[URL(string: "http://pot:4416/ping")!] = .success(Data())
        let journal = CollectingJournal()
        let r = await Verifier(ytdlp: yt, http: feeds, journal: journal, clock: FixedClock(Date())).verify(settings: settings())
        #expect(r.passes)
        #expect(r.ytdlpVersion == "2026.08.19")
        #expect(r.potProvider == .ok && r.cookies == .off && r.egress == "proxy")
        #expect(yt.calls[1].contains("--proxy") && yt.calls[1].last == "https://www.youtube.com/watch?v=jNQXAC9IVRw")
        #expect(journal.entries.last?.detail == "yt-dlp 2026.08.19, extraction ok, cookies off, PO tokens ok, egress proxy")
    }

    /// A flagged address, with a live PO token provider.
    @Test func theBotCheckFailsVerifyWithItsCause() async {
        let yt = FakeYtDlp()
        yt.steps = [.init(result: FakeYtDlp.ok(Data("2026.08.19".utf8))),
                    .init(result: FakeYtDlp.fail(Fixture.text("errors/bot-check.txt"))),
                    .init(result: FakeYtDlp.fail(Fixture.text("errors/bot-check.txt")))]
        let r = await Verifier(ytdlp: yt, http: FakeFeeds(), journal: CollectingJournal(), clock: FixedClock(Date()))
            .verify(settings: settings(cookies: true))
        #expect(!r.passes)
        #expect(r.cause == .botCheck)
        #expect(r.cookies != .ok)
        #expect(r.potProvider != .ok)
        #expect(yt.calls[2].contains("--cookies"))
    }
}

extension VerifierTests {
    func verifyCookies(_ result: ProcessResult) async -> (Verifier.Report, FakeYtDlp) {
        let yt = FakeYtDlp()
        yt.steps = [.init(result: FakeYtDlp.ok(Data("2026.08.19".utf8))), .init(result: FakeYtDlp.ok()), .init(result: result)]
        let r = await Verifier(ytdlp: yt, http: FakeFeeds(), journal: CollectingJournal(), clock: FixedClock(Date()))
            .verify(settings: settings(cookies: true, pot: false))
        return (r, yt)
    }

    @Test func theCookiesAreCheckedAgainstAFeedOnlyASignedInAccountHas() async {
        let (r, yt) = await verifyCookies(FakeYtDlp.ok())
        #expect(r.cookies == .ok)
        #expect(yt.calls[2].last == ":ytsubs" && yt.calls[2].contains("--cookies") && yt.calls[2].contains("--proxy"))
        #expect(!yt.calls[2].contains("--no-warnings"))
    }

    /// YouTube had cleared LOGIN_INFO, and
    /// the public video still played.
    @Test func aJarWithoutASessionFails() async {
        let (r, _) = await verifyCookies(FakeYtDlp.fail("ERROR: [youtube:subscriptions] Login details are needed to download this content. Use --cookies-from-browser or --cookies for the authentication."))
        #expect(r.cookies == .failed("the cookies are not a signed-in session"))
        #expect(r.passes)
    }

    @Test func aSessionEndedMidRequestFails() async {
        let rotated = ProcessResult(exitCode: 0, stdout: Data(), stderr: "WARNING: [youtube:tab] The provided YouTube account cookies are no longer valid. They have likely been rotated in the browser as a security measure.")
        let (r, _) = await verifyCookies(rotated)
        #expect(r.cookies == .failed("the session was signed out or rotated away"))
    }
}

@Suite struct UpdateTests {
    let release = YtDlpRelease.Release(tagName: "2026.09.30", assets: [
        .init(name: "yt-dlp_linux", browserDownloadURL: "https://github.com/yt-dlp/yt-dlp/releases/download/2026.09.30/yt-dlp_linux"),
        .init(name: "yt-dlp_linux_aarch64", browserDownloadURL: "https://x/aarch64"),
        .init(name: "SHA2-256SUMS", browserDownloadURL: "https://x/SHA2-256SUMS"),
    ])

    @Test func aNewerReleaseIsPlanned() {
        let p = YtDlpRelease.plan(release, current: "2026.08.19", asset: YtDlpRelease.assetName(os: "linux", arch: "x86_64"))
        #expect(p?.version == "2026.09.30")
        #expect(p?.binaryURL.hasSuffix("/yt-dlp_linux") == true)
        #expect(YtDlpRelease.plan(release, current: "2026.09.30", asset: "yt-dlp_linux") == nil)
        #expect(YtDlpRelease.assetName(os: "linux", arch: "aarch64") == "yt-dlp_linux_aarch64")
    }

    @Test func theChecksumIsReadFromTheSumsFile() {
        let sums = """
        1111111111111111111111111111111111111111111111111111111111111111  yt-dlp
        ABCDEF0000000000000000000000000000000000000000000000000000000000  yt-dlp_linux
        2222222222222222222222222222222222222222222222222222222222222222  yt-dlp_linux_aarch64
        """
        #expect(YtDlpRelease.checksum(for: "yt-dlp_linux", in: sums) == "abcdef0000000000000000000000000000000000000000000000000000000000")
        #expect(YtDlpRelease.checksum(for: "yt-dlp_macos", in: sums) == nil)
    }

    @Test func theReleaseJSONDecodes() throws {
        let json = #"{"tag_name":"2026.08.19","assets":[{"name":"yt-dlp_linux","browser_download_url":"https://u","size":1}]}"#
        let r = try JSONDecoder().decode(YtDlpRelease.Release.self, from: Data(json.utf8))
        #expect(r.tagName == "2026.08.19" && r.assets.count == 1)
    }
}

@Suite struct CookieAlertTests {
    static let noon = Date(timeIntervalSince1970: 1_790_000_000)
    static let farExpiry = noon.addingTimeInterval(365 * 86_400)

    func report(cookies: Verifier.Check, extraction: Verifier.Check = .ok, at: Date = noon) -> Verifier.Report {
        Verifier.Report(at: at, ytdlpVersion: "2026.08.19", extraction: extraction, cause: nil,
                        cookies: cookies, potProvider: .ok, egress: "proxy")
    }

    func send(_ a: inout CookieAlerts, _ r: Verifier.Report, expiry: Date? = farExpiry) -> [String] {
        a.messages(for: r, expiry: expiry, time: { _ in "14:20" }, day: { _ in "2026-10-05" })
    }

    @Test func aFailureIsSentOnceNotHourly() {
        var a = CookieAlerts()
        #expect(send(&a, report(cookies: .ok)).isEmpty)
        let first = send(&a, report(cookies: .failed("Sign in to confirm you're not a bot")))
        #expect(first == ["The YouTube cookies stopped working at 14:20 (Sign in to confirm you're not a bot). Upload a fresh cookies.txt on Cylindarr's settings page."])
        #expect(send(&a, report(cookies: .failed("again"))).isEmpty)
        #expect(send(&a, report(cookies: .failed("and again"))).isEmpty)
    }

    @Test func workingAgainIsQuietAndRearms() {
        var a = CookieAlerts()
        _ = send(&a, report(cookies: .failed("x")))
        #expect(send(&a, report(cookies: .ok)).isEmpty)
        #expect(send(&a, report(cookies: .failed("y"))).count == 1)
    }

    @Test func whenEverythingIsBlockedTheCookiesAreNotBlamed() {
        var a = CookieAlerts()
        #expect(send(&a, report(cookies: .failed("bot"), extraction: .failed("bot"))).isEmpty)
        #expect(!a.failing)
        // And a failure already reported is not reported again after the outage.
        _ = send(&a, report(cookies: .failed("x")))
        _ = send(&a, report(cookies: .failed("bot"), extraction: .failed("bot")))
        #expect(send(&a, report(cookies: .failed("x"))).isEmpty)
    }

    @Test func noCookiesMeansNoAlerts() {
        var a = CookieAlerts()
        _ = send(&a, report(cookies: .failed("x")))
        #expect(send(&a, report(cookies: .off), expiry: nil).isEmpty)
        #expect(!a.failing)
    }

    @Test func aWeekBeforeExpiryWarnsOncePerJar() {
        var a = CookieAlerts()
        let soon = Self.noon.addingTimeInterval(3 * 86_400)
        #expect(send(&a, report(cookies: .ok), expiry: soon) == ["The YouTube cookies expire on 2026-10-05. Upload a fresh cookies.txt on Cylindarr's settings page before then."])
        #expect(send(&a, report(cookies: .ok), expiry: soon).isEmpty)
        let nextJarSoon = Self.noon.addingTimeInterval(5 * 86_400)
        #expect(send(&a, report(cookies: .ok), expiry: nextJarSoon).count == 1)
        #expect(send(&a, report(cookies: .ok), expiry: Self.noon.addingTimeInterval(8 * 86_400)).isEmpty)
    }

    @Test func aDeadSessionDoesNotAlsoWarnOfExpiry() {
        var a = CookieAlerts()
        let soon = Self.noon.addingTimeInterval(86_400)
        #expect(send(&a, report(cookies: .failed("x")), expiry: soon).count == 1)
    }
}
