import Foundation
import Testing
@testable import CylindarrKit

@Suite struct ArtworkTests {
    @Test func aChannelsAvatarAndBanner() throws {
        let l = try Listing.decode(Fixture.data("ytdlp/artwork-channel-technology-connections.json"))
        let art = Artwork.forChannel(l.thumbnails ?? [])
        #expect(art["poster.jpg"]?.absoluteString.hasSuffix("=s0") == true)
        #expect(art["poster.jpg"]?.absoluteString.contains("/ytc/") == true)
        #expect(art["fanart.jpg"]?.absoluteString.hasPrefix("https://yt3.googleusercontent.com/rhWRZw7") == true)
        #expect(art["banner.jpg"]?.absoluteString.contains("=w2560") == true)
    }

    @Test func aPlaylistsLeadStill() throws {
        let l = try Listing.decode(Fixture.data("ytdlp/artwork-playlist-dream-logic.json"))
        #expect(Artwork.forPlaylist(l.thumbnails ?? []) == ["fanart.jpg": URL(string: "https://i.ytimg.com/vi/snyvQ9COmb8/maxresdefault.jpg")!])
        #expect(l.channelID == "UCu-3YlvaBS4bsya-1eFi62w")
    }

    @Test func nothingToWorkWith() {
        #expect(Artwork.forChannel([]).isEmpty)
        #expect(Artwork.forPlaylist([]).isEmpty)
    }
}
