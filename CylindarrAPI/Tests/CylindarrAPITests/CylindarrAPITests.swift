import Foundation
import Testing
@testable import CylindarrAPI

@Suite struct PairingLinkTests {
    @Test func aLinkReadsBackAsItsServerAndKey() throws {
        let link = CylindarrAPI.pairingLink(server: "http://media.local:8295", key: "a1b2&c3")
        #expect(link.hasPrefix("cylindarr://pair?"))
        let parsed = try #require(CylindarrAPI.parsePairingLink(link))
        #expect(parsed.server.absoluteString == "http://media.local:8295")
        #expect(parsed.key == "a1b2&c3")
    }

    @Test func somethingElseIsNotALink() {
        #expect(CylindarrAPI.parsePairingLink("https://example.com/pair?url=http://x&key=k") == nil)
        #expect(CylindarrAPI.parsePairingLink("cylindarr://pair?url=ftp://x&key=k") == nil)
        #expect(CylindarrAPI.parsePairingLink("cylindarr://pair?url=http://x") == nil)
    }
}

@Suite struct WireTests {
    /// The browser extension reads this JSON by hand; its field names are
    /// part of the API.
    @Test func aGrabResponseHasTheFieldsTheBrowserExtensionReads() throws {
        let grab = Grab(key: "vimeo.76979871", title: "A talk", state: .wanted, position: 2,
                        sourceURL: "https://vimeo.com/76979871", rowPath: "/subscriptions/x#v-vimeo.76979871",
                        added: Date(timeIntervalSince1970: 1_790_000_000))
        let data = try CylindarrAPI.encoder().encode(GrabResponse(outcome: .queued, message: "Queued, 2nd in line.", grab: grab))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["outcome"] as? String == "queued")
        #expect(json["message"] as? String == "Queued, 2nd in line.")
        let g = try #require(json["grab"] as? [String: Any])
        #expect(g["state"] as? String == "wanted")
        #expect(g["added"] as? String == "2026-09-21T14:13:20Z")
        let back = try CylindarrAPI.decoder().decode(GrabResponse.self, from: data)
        #expect(back.grab == grab)
    }
}
