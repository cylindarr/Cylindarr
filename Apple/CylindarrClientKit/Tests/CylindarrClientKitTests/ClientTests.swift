import Foundation
import Testing
@testable import CylindarrClientKit

/// Answers every request from a table, and remembers what was asked.
final class StubServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answers: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var seen: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var r = request
        if r.httpBody == nil, let stream = r.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            r.httpBody = data
        }
        Self.seen.append(r)
        let key = "\(request.httpMethod ?? "GET") \(request.url!.path())"
        let (status, body) = Self.answers[key] ?? (404, #"{"error":true,"reason":"Not Found"}"#)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubServer.self]
        return URLSession(configuration: c)
    }
}

let pairing = Pairing(server: URL(string: "http://nas.local:8295")!, key: "k1")

@Suite(.serialized) struct ClientTests {
    init() { StubServer.answers = [:]; StubServer.seen = [] }

    @Test func aGrabSendsTheKeyAndTheLink() async throws {
        StubServer.answers["POST /api/v1/grabs"] = (202, #"{"outcome":"queued","message":"Queued, next in line.","grab":{"key":"snyvQ9COmb8","title":"snyvQ9COmb8","state":"wanted","position":1,"sourceURL":"https://www.youtube.com/watch?v=snyvQ9COmb8","rowPath":"/subscriptions/x#v-snyvQ9COmb8","added":"2026-10-02T19:07:27Z"}}"#)
        let answer = try await CylindarrClient(pairing: pairing, session: StubServer.session()).grab("https://youtu.be/snyvQ9COmb8")
        #expect(answer.outcome == .queued)
        #expect(answer.grab?.position == 1)
        let sent = try #require(StubServer.seen.first)
        #expect(sent.value(forHTTPHeaderField: "X-Api-Key") == "k1")
        #expect(try CylindarrAPI.decoder().decode(GrabRequest.self, from: sent.httpBody!).url == "https://youtu.be/snyvQ9COmb8")
    }

    /// A refusal is an answer, not a failure: the card shows its message.
    @Test func aRefusalComesBackAsAnAnswer() async throws {
        StubServer.answers["POST /api/v1/grabs"] = (422, #"{"outcome":"followable","message":"That's a YouTube channel.","follow":{"kind":"channel","url":"https://www.youtube.com/@x"}}"#)
        let answer = try await CylindarrClient(pairing: pairing, session: StubServer.session()).grab("https://www.youtube.com/@x")
        #expect(answer.outcome == .followable)
        #expect(answer.follow?.kind == "channel")
    }

    @Test func aWrongKeySaysSo() async {
        StubServer.answers["GET /api/v1/status"] = (401, #"{"error":true,"reason":"Send the key"}"#)
        await #expect(throws: CylindarrClient.Failure.badKey) {
            try await CylindarrClient(pairing: pairing, session: StubServer.session()).status()
        }
    }

    @Test func aServerErrorCarriesItsReason() async {
        StubServer.answers["POST /api/v1/subscriptions"] = (422, #"{"error":true,"reason":"Already followed."}"#)
        await #expect(throws: CylindarrClient.Failure.server(422, "Already followed.")) {
            try await CylindarrClient(pairing: pairing, session: StubServer.session()).follow(url: "https://www.youtube.com/@x")
        }
    }

    @MainActor @Test func aQueuedCardClosesItselfAndAQuestionDoesNot() async {
        StubServer.answers["POST /api/v1/grabs"] = (202, #"{"outcome":"queued","message":"Queued."}"#)
        let card = GrabCard(link: "https://framatube.org/w/x", pairing: pairing, session: StubServer.session())
        await card.send()
        #expect(card.closesItself)
        #expect(card.headline == "Grabbed")
        StubServer.answers["POST /api/v1/grabs"] = (422, #"{"outcome":"followable","message":"Follow?","follow":{"kind":"playlist","url":"u"}}"#)
        let question = GrabCard(link: "https://www.youtube.com/playlist?list=PLx", pairing: pairing, session: StubServer.session())
        await question.send()
        #expect(!question.closesItself)
        StubServer.answers["POST /api/v1/subscriptions"] = (201, #"{"id":"1","name":"Dream Logic","message":"Following Dream Logic.","pagePath":"/subscriptions/1"}"#)
        await question.follow()
        #expect(question.headline == "Following Dream Logic")
        #expect(question.pageURL?.absoluteString == "http://nas.local:8295/subscriptions/1")
    }

    @MainActor @Test func anUnpairedCardSaysSoWithoutCalling() async {
        let card = GrabCard(link: "https://x.com/v", pairing: nil)
        await card.send()
        #expect(card.phase == .unpaired)
        #expect(StubServer.seen.isEmpty)
    }
}

@Suite struct PairingTests {
    @Test func anAddressWithoutASchemeIsHTTP() {
        #expect(Pairing(address: "nas.local:8295/", key: " k ")?.server.absoluteString == "http://nas.local:8295")
        #expect(Pairing(address: "nas.local:8295", key: " k ")?.key == "k")
        #expect(Pairing(address: "", key: "k") == nil)
        #expect(Pairing(address: "nas.local", key: "") == nil)
    }

    @Test func thePairingLinkFromTheSettingsPage() {
        let p = Pairing(link: "cylindarr://pair?url=http://nas.local:8295&key=0123456789abcdef0123456789abcdef")
        #expect(p?.displayAddress == "nas.local:8295")
        #expect(p?.key == "0123456789abcdef0123456789abcdef")
    }

    @Test(arguments: [
        ("https://www.youtube.com/watch?v=snyvQ9COmb8", "https://www.youtube.com/watch?v=snyvQ9COmb8"),
        ("Watch this: https://framatube.org/w/9c9de5e8 it's good", "https://framatube.org/w/9c9de5e8"),
        ("no link here", nil),
    ])
    func theLinkInWhatWasShared(text: String, link: String?) {
        #expect(SharedLink.find(in: text) == link)
    }
}
