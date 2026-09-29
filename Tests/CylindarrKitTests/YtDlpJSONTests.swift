import Foundation
import Testing
@testable import CylindarrKit

@Suite struct YtDlpJSONTests {
    @Test func aVideo() throws {
        let v = try VideoInfo.decode(Fixture.data("ytdlp/video-dream-logic-snyvQ9COmb8.json"))
        #expect(v.id == "snyvQ9COmb8")
        #expect(v.title == "When AI Stops Feeling Magical: Greg Hochmuth")
        #expect(v.channelID == "UCu-3YlvaBS4bsya-1eFi62w")
        #expect(v.liveStatus == .notLive)
        #expect(v.duration == 265)
        #expect(!v.isShort)
        #expect(!v.isLivestreamRecording)
        #expect(v.uploaded == Date(timeIntervalSince1970: 1754395301))
        #expect(v.uploadDate == "20250805")
    }

    @Test func aDateOnlyVideoLandsAtNoonUTC() throws {
        let json = #"{"id":"AAAAAAAAAAA","title":"t","upload_date":"20170718"}"#
        let v = try VideoInfo.decode(Data(json.utf8))
        #expect(v.uploaded == Fixture.date("2017-07-18T12:00:00Z"))
    }

    /// Pinchflat crashed on a video whose metadata it did not expect. Nothing
    /// but id and title is required here.
    @Test func missingFieldsAreNotAnError() throws {
        let v = try VideoInfo.decode(Data(#"{"id":"AAAAAAAAAAA","title":"t"}"#.utf8))
        #expect(v.uploaded == nil)
        #expect(v.liveStatus == nil)
    }

    @Test func aShortIsRecognisedByMediaTypeOrURL() throws {
        let a = try VideoInfo.decode(Data(#"{"id":"AAAAAAAAAAA","title":"t","media_type":"short"}"#.utf8))
        let b = try VideoInfo.decode(Data(#"{"id":"AAAAAAAAAAA","title":"t","webpage_url":"https://www.youtube.com/shorts/AAAAAAAAAAA"}"#.utf8))
        #expect(a.isShort && b.isShort)
    }

    @Test func aPlaylistListing() throws {
        let l = try Listing.decode(Fixture.data("ytdlp/flat-playlist-dream-logic.json"))
        #expect(l.id == "PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj")
        #expect(l.title == "Dream Logic")
        #expect(l.entries.count == 5)
        #expect(l.entries.contains { $0.id == "snyvQ9COmb8" })
    }

    @Test func aChannelVideosTab() throws {
        let l = try Listing.decode(Fixture.data("ytdlp/flat-channel-videos-technology-connections.json"))
        #expect(l.channelID == "UCy0tKL1T7wFoYcxCe0xjN6Q")
        #expect(l.entries.count == 12)
        #expect(l.entries.first?.id == "0KoeY54M5VA")
        // YouTube tests titles: the feed and the listing disagree about this
        // one on the same afternoon. The NFO takes the title at fetch time.
        #expect(l.entries.first?.title == "Computers made engines so much better at their job")
    }
}
