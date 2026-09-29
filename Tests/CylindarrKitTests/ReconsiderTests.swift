import Foundation
import Testing
@testable import CylindarrKit

@Suite struct ReconsiderTests {
    let now = Fixture.date("2026-09-27T22:00:00Z")
    let sub = UUID()

    func record(_ id: String, exact: String? = nil, approx: String? = nil, state: VideoState = .wanted) -> VideoRecord {
        VideoRecord(id: id, subscriptionID: sub, title: id, uploaded: exact.map(Fixture.date), state: state,
                    firstSeen: now, approximatelyUploaded: approx.map(Fixture.date))
    }

    /// Technology Connections: polled whole, then given a cutoff.
    @Test func aLaterCutoffSkipsWhatIsQueued() {
        let rules = Rules(cutoff: Fixture.date("2026-09-05T05:00:00Z"))
        let changed = Reconsider.changes([
            record("0KoeY54M5VA", exact: "2026-09-24T16:57:27Z"),
            record("F_7B2shTPPU", exact: "2026-08-21T17:27:01Z"),
            record("old", approx: "2026-06-01T00:00:00Z", state: .deferred(.botCheck, until: now)),
            record("near", approx: "2026-09-01T00:00:00Z"),
            record("placed", exact: "2020-01-01T00:00:00Z", state: .placed),
        ], rules: rules, now: now)
        #expect(changed.map(\.id) == ["F_7B2shTPPU", "old"])
        #expect(changed.allSatisfy { $0.state == .skipped(.beforeCutoff) })
    }

    @Test func aTitleFilterAppliesToTheQueueToo() {
        let changed = Reconsider.changes([record("a"), record("b")].map { var r = $0; r.title = $0.id == "a" ? "Trailer" : "Episode"; return r },
                                         rules: Rules(titleExclude: "trailer"), now: now)
        #expect(changed.map(\.id) == ["a"])
    }
}

@Suite struct RetireByRuleTests {
    let now = Fixture.date("2026-09-27T12:00:00Z")
    let sub = UUID()

    func placed(_ id: String, _ day: String) -> VideoRecord {
        VideoRecord(id: id, subscriptionID: sub, title: id, uploaded: Fixture.date(day + "T12:00:00Z"), state: .placed,
                    path: "Shows/X/\(id).mp4", firstSeen: now)
    }

    @Test func theNewestAreKept() {
        let records = [placed("a", "2026-09-01"), placed("b", "2026-09-20"), placed("c", "2026-08-01"), placed("d", "2026-09-10")]
        #expect(RetireByRule.toRetire(records, retention: .newest(2), now: now).map(\.id).sorted() == ["a", "c"])
        #expect(RetireByRule.toRetire(records, retention: .keepAll, now: now).isEmpty)
    }

    @Test func theLastDaysAreKept() {
        let records = [placed("a", "2026-09-01"), placed("b", "2026-09-20"), placed("c", "2026-08-01")]
        #expect(RetireByRule.toRetire(records, retention: .days(14), now: now).map(\.id).sorted() == ["a", "c"])
    }

    /// Only what is placed: a video still waiting is Consider's business.
    @Test func onlyPlacedEpisodesAreRetired() {
        var waiting = placed("w", "2020-01-01")
        waiting.state = .wanted
        waiting.path = nil
        #expect(RetireByRule.toRetire([waiting], retention: .newest(0), now: now).isEmpty)
    }

    @Test func aVideoOlderThanTheLastDaysIsNeverFetched() {
        let rules = Rules(retention: .days(30))
        #expect(Consider.decide(Candidate(id: "a", title: "t", uploaded: Fixture.date("2026-06-01T00:00:00Z")), rules: rules, now: now)
            == .skip(.pastRetention))
        #expect(Consider.decide(Candidate(id: "a", title: "t", uploaded: Fixture.date("2026-09-20T00:00:00Z")), rules: rules, now: now) == .want)
    }
}
