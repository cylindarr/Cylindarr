import Foundation
import Testing
@testable import CylindarrKit

@Suite struct ConsiderTests {
    let day = Fixture.date("2026-09-24T16:57:27Z")

    @Test func aNewUploadIsWanted() {
        #expect(Consider.decide(Candidate(id: "0KoeY54M5VA", title: "Engines", uploaded: day), rules: Rules()) == .want)
    }

    @Test func theCutoffSkips() {
        let rules = Rules(cutoff: Fixture.date("2026-09-05T00:00:00Z"))
        #expect(Consider.decide(Candidate(id: "a", title: "t", uploaded: Fixture.date("2026-09-01T00:00:00Z")), rules: rules) == .skip(.beforeCutoff))
        #expect(Consider.decide(Candidate(id: "a", title: "t", uploaded: day), rules: rules) == .want)
    }

    /// A listing's "3 weeks ago" skips only what is clearly older than the
    /// cutoff; what is near it is wanted and settled by `--dateafter`.
    @Test func approximateDatesSkipOnlyTheClearlyOld() {
        let now = Fixture.date("2026-09-27T12:00:00Z")
        let rules = Rules(cutoff: Fixture.date("2026-08-28T00:00:00Z"))
        func c(_ iso: String) -> Candidate { Candidate(id: "a", title: "t", approximatelyUploaded: Fixture.date(iso)) }
        #expect(Consider.decide(c("2026-09-23T00:00:00Z"), rules: rules, now: now) == .want)
        #expect(Consider.decide(c("2026-08-24T00:00:00Z"), rules: rules, now: now) == .want)
        #expect(Consider.decide(c("2026-07-01T00:00:00Z"), rules: rules, now: now) == .skip(.beforeCutoff))
        // "1 year ago" on a playlist: a quarter of a year's tolerance.
        #expect(Consider.decide(c("2025-09-28T00:00:00Z"), rules: Rules(cutoff: Fixture.date("2025-11-15T00:00:00Z")), now: now) == .want)
        #expect(Consider.decide(c("2025-09-28T00:00:00Z"), rules: Rules(cutoff: Fixture.date("2026-03-01T00:00:00Z")), now: now) == .skip(.beforeCutoff))
    }

    @Test func shortsAreOutByDefault() {
        #expect(Consider.decide(Candidate(id: "a", title: "t", isShort: true), rules: Rules()) == .skip(.short))
        #expect(Consider.decide(Candidate(id: "a", title: "t", isShort: true), rules: Rules(includeShorts: true)) == .want)
    }

    @Test func livestreamsWaitUntilTheyEnd() {
        #expect(Consider.decide(Candidate(id: "a", title: "t", liveStatus: .isLive), rules: Rules()) == .wait(.liveNow))
        #expect(Consider.decide(Candidate(id: "a", title: "t", liveStatus: .wasLive), rules: Rules()) == .want)
        #expect(Consider.decide(Candidate(id: "a", title: "t", liveStatus: .wasLive), rules: Rules(includeLivestreams: false)) == .skip(.livestream))
        #expect(Consider.decide(Candidate(id: "a", title: "t", liveStatus: .isUpcoming), rules: Rules()) == .wait(.premiere))
    }

    /// The feed has no duration. A duration rule passes at poll time and is
    /// applied when yt-dlp's full JSON is read.
    @Test func unknownFactsPassUntilKnown() {
        let rules = Rules(minDuration: 120)
        #expect(Consider.decide(Candidate(id: "a", title: "t"), rules: rules) == .want)
        #expect(Consider.decide(Candidate(id: "a", title: "t", duration: 59), rules: rules) == .skip(.tooShort))
    }

    @Test func titleFilters() {
        let rules = Rules(titleInclude: "full episode", titleExclude: #"\btrailer\b"#)
        #expect(Consider.decide(Candidate(id: "a", title: "SMN Full Episode: Rent"), rules: rules) == .want)
        #expect(Consider.decide(Candidate(id: "a", title: "Full Episode trailer"), rules: rules) == .skip(.titleExcluded))
        #expect(Consider.decide(Candidate(id: "a", title: "A short bit"), rules: rules) == .skip(.titleNotIncluded))
        // A filter that is not a valid regular expression matches as text.
        #expect(Consider.decide(Candidate(id: "a", title: "Q&A [live"), rules: Rules(titleExclude: "[live")) == .skip(.titleExcluded))
    }

    @Test func membersOnlyIsSkipped() throws {
        let info = try VideoInfo.decode(Data(#"{"id":"AAAAAAAAAAA","title":"t","availability":"subscriber_only"}"#.utf8))
        #expect(Consider.decide(Candidate(info), rules: Rules()) == .skip(.membersOnly))
    }

    @Test func theDefaultsAreRoundOnesAnswers() {
        let r = Rules()
        #expect(r.quality == .hd1080)
        #expect(!r.includeShorts && r.includeLivestreams)
        #expect(r.sponsorBlock == .cut && r.sponsorBlockCategories == ["sponsor", "selfpromo", "interaction"])
        #expect(r.retention == .keepAll)
    }
}
