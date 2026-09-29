import Foundation
import Testing
@testable import CylindarrKit

@Suite struct SubtitleCutterTests {
    /// The opening of MIT's "How to Speak" (Unzc731iCUY), whose first 18.221
    /// seconds SponsorBlock marks as a sponsor spot and an interaction reminder.
    let howToSpeak = """
    1
    00:00:19,220 --> 00:00:23,840
    PATRICK WINSTON: The Uniform
    Code of Military Justice

    2
    00:00:23,840 --> 00:00:27,530
    specifies court martial for

    """

    @Test func cuesMoveBackByTheCutBeforeThem() {
        let cues = SubtitleCutter.cut(SubtitleCutter.parse(howToSpeak), removing: CutList([(0, 6.618), (6.618, 18.221)]))
        #expect(cues.count == 2)
        #expect(abs(cues[0].start - 0.999) < 0.001)
        #expect(abs(cues[1].end - 9.309) < 0.001)
        #expect(SubtitleCutter.render(cues).hasPrefix("1\n00:00:00,999 --> 00:00:05,619\nPATRICK WINSTON: The Uniform\nCode of Military Justice\n"))
    }

    @Test func aCueInsideACutGoesAndOneAcrossItsEdgeIsClipped() {
        let cues = [
            SubtitleCutter.Cue(start: 10, end: 12, text: "inside"),
            SubtitleCutter.Cue(start: 18, end: 22, text: "across the end"),
            SubtitleCutter.Cue(start: 30, end: 32, text: "after"),
        ]
        let cut = SubtitleCutter.cut(cues, removing: CutList([(9, 20)]))
        #expect(cut.map(\.text) == ["across the end", "after"])
        #expect(cut[0].start == 9 && cut[0].end == 11)
        #expect(cut[1].start == 19 && cut[1].end == 21)
    }

    @Test func overlappingRangesAreCountedOnce() {
        let cut = SubtitleCutter.cut([.init(start: 100, end: 101, text: "x")], removing: CutList([(10, 20), (15, 30)]))
        #expect(cut.first?.start == 80)
    }

    @Test func crlfAndBOMAreRead() {
        #expect(SubtitleCutter.parse("\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,500\r\nhi\r\n\r\n").first == .init(start: 1, end: 2.5, text: "hi"))
    }

    @Test func languageTags() {
        #expect(SubtitleCutter.languageTag("en-j3PyPqV-e1s") == "en")
        #expect(SubtitleCutter.languageTag("en-GB") == "en-GB")
        #expect(SubtitleCutter.languageTag("pt-BR") == "pt-BR")
        #expect(SubtitleCutter.languageTag("zh-Hans") == "zh")
        #expect(SubtitleCutter.languageTag("en") == "en")
    }
}
