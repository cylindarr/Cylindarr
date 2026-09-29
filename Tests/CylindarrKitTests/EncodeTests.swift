import Foundation
import Testing
@testable import CylindarrKit

@Suite struct CutListTests {
    @Test func overlappingAndTouchingSegmentsMerge() {
        let cuts = CutList([(15, 30), (10, 20), (30, 31), (50, 50)])
        #expect(cuts.removed == [.init(start: 10, end: 31)])
    }

    @Test func timesMoveBackByTheCutsBeforeThem() {
        let cuts = CutList([(10, 20), (30, 40)])
        #expect(cuts.map(5) == 5)
        #expect(cuts.map(15) == 10)
        #expect(cuts.map(25) == 15)
        #expect(cuts.map(50) == 30)
    }

    @Test func onlyTheChosenCategoriesAreCut() {
        let segments = [VideoInfo.SponsorBlockSegment(category: "sponsor", startTime: 1, endTime: 2),
                        VideoInfo.SponsorBlockSegment(category: "filler", startTime: 3, endTime: 4),
                        VideoInfo.SponsorBlockSegment(category: "selfpromo", startTime: 5, endTime: nil)]
        #expect(CutList(segments: segments, categories: ["sponsor", "selfpromo"]).removed == [.init(start: 1, end: 2)])
    }
}

@Suite struct TranscodeTests {
    let qsv = EncodeSettings(encoder: .quickSync(device: "/dev/dri/renderD129"), quality: 24)

    func value(after flag: String, in a: [String]) -> String? {
        a.firstIndex(of: flag).map { a[$0 + 1] }
    }

    @Test func uncutVideoIsEncodedAndItsAACCopied() {
        let a = Transcode.arguments(input: "/s/x.mp4", output: "/s/x.hevc.mp4", cuts: CutList([]), chapters: nil,
                                    hasAudio: true, audioIsAAC: true, settings: qsv)
        #expect(value(after: "-init_hw_device", in: a) == "vaapi=va:/dev/dri/renderD129")
        #expect(value(after: "-vf", in: a) == "format=nv12,hwupload=extra_hw_frames=64")
        #expect(value(after: "-c:v", in: a) == "hevc_qsv")
        #expect(value(after: "-q:v", in: a) == "24")
        #expect(value(after: "-low_power", in: a) == "1")
        #expect(value(after: "-tag:v", in: a) == "hvc1")
        #expect(value(after: "-c:a", in: a) == "copy")
        #expect(value(after: "-map_chapters", in: a) == "0")
        #expect(a.last == "/s/x.hevc.mp4")
    }

    @Test func opusIsEncodedToAAC() {
        let a = Transcode.arguments(input: "i", output: "o", cuts: CutList([]), chapters: nil, hasAudio: true, audioIsAAC: false, settings: qsv)
        #expect(value(after: "-c:a", in: a) == "aac")
    }

    /// Video and audio drop the same ranges and move by the same amounts,
    /// so there is nothing for a player to drift on.
    @Test func cutsSelectAndShiftVideoAndAudioAlike() {
        let cuts = CutList([(7.438, 12.683), (917.877, 1143.509)])
        let a = Transcode.arguments(input: "i", output: "o", cuts: cuts, chapters: "/s/x.chapters.txt",
                                    hasAudio: true, audioIsAAC: true, settings: qsv)
        let select = "not(gte(t,7.438)*lt(t,12.683)+gte(t,917.877)*lt(t,1143.509))"
        let shift = "gte(T,12.683)*5.245+gte(T,1143.509)*225.632"
        #expect(value(after: "-vf", in: a) == "select='\(select)',setpts='PTS-(\(shift))/TB',format=nv12,hwupload=extra_hw_frames=64")
        #expect(value(after: "-af", in: a) == "aselect='\(select)',asetpts='PTS-(\(shift))/TB',aresample=async=1")
        #expect(value(after: "-fps_mode", in: a) == "vfr")
        #expect(value(after: "-c:a", in: a) == "aac")
        #expect(a.contains("/s/x.chapters.txt"))
        #expect(value(after: "-map_chapters", in: a) == "1")
    }

    @Test func theCPUIsUsedWithoutQuickSync() {
        let a = Transcode.arguments(input: "i", output: "o", cuts: CutList([]), chapters: nil, hasAudio: true, audioIsAAC: true,
                                    settings: EncodeSettings(encoder: .software, quality: 24))
        #expect(!a.contains("-init_hw_device"))
        #expect(value(after: "-c:v", in: a) == "libx265")
        #expect(value(after: "-crf", in: a) == "24")
    }

    @Test func quickSyncsDefaultModeHasNoLowPowerFlag() {
        let a = Transcode.arguments(input: "i", output: "o", cuts: CutList([]), chapters: nil, hasAudio: true, audioIsAAC: true,
                                    settings: EncodeSettings(encoder: .quickSync(device: "/dev/dri/renderD128", lowPower: false)))
        #expect(value(after: "-c:v", in: a) == "hevc_qsv")
        #expect(!a.contains("-low_power"))
        #expect(qsv.withoutLowPower?.encoder == .quickSync(device: "/dev/dri/renderD129", lowPower: false))
        #expect(EncodeSettings(encoder: .software).withoutLowPower == nil)
    }

    @Test func vaapiUploadsToItsOwnDevice() {
        let a = Transcode.arguments(input: "i", output: "o", cuts: CutList([]), chapters: nil, hasAudio: true, audioIsAAC: true,
                                    settings: EncodeSettings(encoder: .vaapi(device: "/dev/dri/renderD128"), quality: 26))
        #expect(value(after: "-init_hw_device", in: a) == "vaapi=va:/dev/dri/renderD128")
        #expect(value(after: "-filter_hw_device", in: a) == "va")
        #expect(value(after: "-vf", in: a) == "format=nv12,hwupload")
        #expect(value(after: "-c:v", in: a) == "hevc_vaapi")
        #expect(value(after: "-qp", in: a) == "26")
    }

    @Test func nvencTakesFramesFromMemory() {
        let a = Transcode.arguments(input: "i", output: "o", cuts: CutList([]), chapters: nil, hasAudio: true, audioIsAAC: true,
                                    settings: EncodeSettings(encoder: .nvenc))
        #expect(!a.contains("-init_hw_device"))
        #expect(value(after: "-c:v", in: a) == "hevc_nvenc")
        #expect(value(after: "-rc", in: a) == "constqp")
        #expect(value(after: "-tag:v", in: a) == "hvc1")
    }

    @Test func chaptersMoveWithTheCuts() throws {
        let chapters = [VideoInfo.Chapter(title: "Intro", startTime: 0, endTime: 10),
                        VideoInfo.Chapter(title: "Ad", startTime: 10, endTime: 20),
                        VideoInfo.Chapter(title: "Part 1; the = sign", startTime: 20, endTime: 100)]
        let text = try #require(Transcode.chapters(chapters, cuts: CutList([(10, 20)])))
        #expect(text == """
        ;FFMETADATA1
        [CHAPTER]
        TIMEBASE=1/1000
        START=0
        END=10000
        title=Intro
        [CHAPTER]
        TIMEBASE=1/1000
        START=10000
        END=90000
        title=Part 1\\; the \\= sign

        """)
    }

    @Test func noChaptersLeftMeansNoFile() {
        #expect(Transcode.chapters([], cuts: CutList([(1, 2)])) == nil)
    }
}

@Suite struct FormatSelectorTests {
    @Test func theBestSDRSourceAtTheHeight() {
        #expect(FormatSelector.formatArgument(for: .hd1080)
            == "bv*[height<=1080][dynamic_range=?SDR][protocol^=http]+ba[acodec^=mp4a]/bv*[height<=1080][dynamic_range=?SDR][protocol^=http]+ba/bv*[height<=1080]+ba/b[height<=1080]/b")
        #expect(FormatSelector.sortArgument(for: .uhd2160) == "res:2160")
    }
}
