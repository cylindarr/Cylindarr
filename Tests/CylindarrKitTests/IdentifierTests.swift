import Foundation
import Testing
@testable import CylindarrKit

@Suite struct IdentifierTests {
    @Test(arguments: [
        ("https://www.youtube.com/@TechnologyConnections", YouTubeTarget.handle("TechnologyConnections")),
        ("https://www.youtube.com/@Asianometry/videos", .handle("Asianometry")),
        ("youtube.com/@Asianometry", .handle("Asianometry")),
        ("@Asianometry", .handle("Asianometry")),
        ("https://www.youtube.com/channel/UCy0tKL1T7wFoYcxCe0xjN6Q", .channel("UCy0tKL1T7wFoYcxCe0xjN6Q")),
        ("UCy0tKL1T7wFoYcxCe0xjN6Q", .channel("UCy0tKL1T7wFoYcxCe0xjN6Q")),
        ("https://www.youtube.com/playlist?list=PLjBgBnF4euu8NfDvz0W-czHx6bbkPIWNU", .playlist("PLjBgBnF4euu8NfDvz0W-czHx6bbkPIWNU")),
        ("PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj", .playlist("PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj")),
        ("https://www.youtube.com/watch?v=0KoeY54M5VA", .video("0KoeY54M5VA")),
        ("https://www.youtube.com/watch?v=0KoeY54M5VA&list=PLDQ6BYd73QHxthC8dcgT6ovfGEOBYjhhj", .video("0KoeY54M5VA")),
        ("https://youtu.be/0KoeY54M5VA?si=abc", .video("0KoeY54M5VA")),
        ("https://m.youtube.com/watch?v=0KoeY54M5VA", .video("0KoeY54M5VA")),
        ("https://www.youtube.com/shorts/0KoeY54M5VA", .video("0KoeY54M5VA")),
        ("https://www.youtube.com/live/0KoeY54M5VA", .video("0KoeY54M5VA")),
        ("0KoeY54M5VA", .video("0KoeY54M5VA")),
        ("https://www.youtube.com/c/SomeMoreNews", .legacyName("SomeMoreNews")),
        ("https://www.youtube.com/user/techconnectify", .legacyName("techconnectify")),
        ("https://vimeo.com/76979871", .other(URL(string: "https://vimeo.com/76979871")!)),
    ])
    func parses(input: String, expected: YouTubeTarget) {
        #expect(Identifier.parse(input) == expected)
    }

    @Test func rubbishIsNothing() {
        #expect(Identifier.parse("") == nil)
        #expect(Identifier.parse("   ") == nil)
        #expect(Identifier.parse("https://youtu.be/") == nil)
    }

    @Test func aChannelPageGivesItsID() {
        let html = #"<html>…"metadata":{"channelMetadataRenderer":{"title":"Technology Connections","externalId":"UCy0tKL1T7wFoYcxCe0xjN6Q","ownerUrls":[]}}…"#
        #expect(Identifier.channelID(inChannelPage: html) == "UCy0tKL1T7wFoYcxCe0xjN6Q")
        #expect(Identifier.channelID(inChannelPage: "<html></html>") == nil)
    }

    @Test func subscriptionsListTheVideosTabNotTheChannelRoot() {
        let s = Subscription(kind: .channel, youtubeID: "UCy0tKL1T7wFoYcxCe0xjN6Q", name: "Technology Connections")
        #expect(s.listingURL.absoluteString == "https://www.youtube.com/channel/UCy0tKL1T7wFoYcxCe0xjN6Q/videos")
        #expect(s.feedURL.absoluteString == "https://www.youtube.com/feeds/videos.xml?channel_id=UCy0tKL1T7wFoYcxCe0xjN6Q")
    }
}
