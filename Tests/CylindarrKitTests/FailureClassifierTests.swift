import Foundation
import Testing
@testable import CylindarrKit

@Suite struct FailureClassifierTests {
    @Test func theBotCheckDefers() {
        #expect(FailureClassifier.diagnose(stderr: Fixture.text("errors/bot-check.txt")) == .deferred(.botCheck))
    }

    /// Pinchflat's `last_error` for 0KoeY54M5VA: a warning line first. The
    /// warning must not decide the cause.
    @Test func warningsBeforeTheErrorAreIgnored() {
        let stderr = """
        WARNING: [youtube] No title found in player responses; falling back to title from initial data. Other metadata may also be missing
        ERROR: [youtube] 0KoeY54M5VA: Sign in to confirm you’re not a bot. Use --cookies-from-browser or --cookies for the authentication.
        """
        #expect(FailureClassifier.diagnose(stderr: stderr) == .deferred(.botCheck))
    }

    @Test func theAgeGateAsksForCookies() {
        #expect(FailureClassifier.diagnose(stderr: Fixture.text("errors/age-gate.txt")) == .needsCookies(then: .ageRestricted))
    }

    /// yt-dlp 2026.07.04, 2026-09-27; 2026.08.19 fetched the same video.
    @Test func aForbiddenStreamWaitsForAnUpdate() {
        #expect(FailureClassifier.diagnose(stderr: Fixture.text("errors/stream-forbidden.txt")) == .deferred(.streamForbidden))
    }

    /// yt-dlp 2026.08.19 on 2026-10-07, for a video in a playlist 14 hours
    /// before it was public. The same words cover a removed video, so it
    /// waits, and fails as removed after about two weeks.
    @Test func aBareUnavailableWaits() throws {
        #expect(FailureClassifier.diagnose(stderr: Fixture.text("errors/unavailable.txt")) == .deferred(.unavailable))
        #expect(FailureClassifier.diagnose(stderr: "ERROR: [youtube] AAAAAAAAAAA: Video unavailable") == .deferred(.unavailable))
        #expect(DeferCause.unavailable.failsAs == .removed)
        #expect(DeferCause.unknown.failsAs == .gaveUp)
        let limit = try #require(DeferCause.unavailable.attemptLimit)
        let waited = (1..<limit).map { DeferCause.unavailable.backoff(afterAttempt: $0) }.reduce(0, +)
        #expect((13 * 86400...16 * 86400).contains(waited))
    }

    @Test(arguments: [
        ("private", Diagnosis.needsCookies(then: .privateVideo)),
        ("removed", .failed(.removed)),
        ("terminated", .failed(.removed)),
        ("geo", .failed(.geoBlocked)),
        ("members", .needsCookies(then: .membersOnly)),
        ("premiere", .deferred(.premiere)),
        ("upcoming", .deferred(.premiere)),
        ("rate", .deferred(.rateLimited)),
        ("format", .failed(.formatUnavailable)),
        ("network", .deferred(.network)),
        ("disk", .deferred(.lowDisk)),
    ])
    func transcribed(cause: String, expected: Diagnosis) throws {
        let rows = Fixture.text("errors/transcribed.txt").split(separator: "\n").map { $0.split(separator: "\t", maxSplits: 1) }
        let line = try #require(rows.first { $0.first.map(String.init) == cause }?.last)
        #expect(FailureClassifier.diagnose(stderr: String(line)) == expected)
    }

    @Test func somethingNewDefersOnceAsUnknown() {
        #expect(FailureClassifier.diagnose(stderr: "ERROR: [youtube] X: something YouTube invented today") == .deferred(.unknown))
        #expect(DeferCause.unknown.attemptLimit == 2)
    }

    @Test func theBotCheckBacksOffLongest() {
        #expect(DeferCause.botCheck.backoff(afterAttempt: 1) == 3600)
        #expect(DeferCause.botCheck.backoff(afterAttempt: 4) == 24 * 3600)
        #expect(DeferCause.botCheck.backoff(afterAttempt: 40) == 24 * 3600)
        #expect(DeferCause.network.backoff(afterAttempt: 1) == 300)
    }
}
