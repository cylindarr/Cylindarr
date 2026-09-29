import Foundation
import Testing
@testable import CylindarrKit

@Suite struct FeedTests {
    @Test func channelFeedListsTheFifteenNewest() throws {
        let feed = try FeedParser.parse(Fixture.data("feeds/channel-technology-connections.xml"))
        #expect(feed.title == "Technology Connections")
        #expect(feed.channelID == "UCy0tKL1T7wFoYcxCe0xjN6Q")
        #expect(feed.playlistID == nil)
        #expect(feed.entries.count == 15)
        let newest = try #require(feed.entries.first)
        #expect(newest.videoID == "0KoeY54M5VA")
        #expect(newest.published == Fixture.date("2026-09-24T16:57:27Z"))
        #expect(newest.title.hasPrefix("Engines haven't been fully mechanical"))
        #expect(feed.entries.allSatisfy { Identifier.isVideoID($0.videoID) })
    }

    @Test func playlistFeedCarriesItsPlaylistAndChannel() throws {
        let feed = try FeedParser.parse(Fixture.data("feeds/playlist-dream-logic.xml"))
        #expect(feed.title == "Dream Logic")
        #expect(feed.playlistID == "PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj")
        #expect(feed.channelID == "UCu-3YlvaBS4bsya-1eFi62w")
        #expect(feed.author == "Kirby Ferguson")
        #expect(feed.entries.count == 5)
        #expect(feed.entries.first?.description.contains("Greg Hochmuth") == true)
    }

    /// YouTube answers about half of playlist feed requests with this page.
    @Test func theNotFoundPageIsNotAFeed() {
        #expect(throws: FeedError.notAFeed) { try FeedParser.parse(Fixture.data("feeds/not-found.html")) }
    }

    @Test func emptyBodyIsNotAFeed() {
        #expect(throws: FeedError.notAFeed) { try FeedParser.parse(Data()) }
    }
}
