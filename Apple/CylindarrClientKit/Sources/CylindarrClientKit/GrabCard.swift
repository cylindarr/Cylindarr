import Foundation
import Observation

/// What the share sheet, the Services menu and the app's own Grab command
/// show: the link goes to the server at once, and the card says what
/// happened. A grab that was queued closes itself; anything that asks a
/// question (follow this channel?) or went wrong stays until dismissed.
@MainActor @Observable
public final class GrabCard: Identifiable {
    public enum Phase: Equatable {
        case sending
        case answered(GrabResponse)
        case following
        case followed(FollowResponse)
        case problem(String)
        /// No server paired yet.
        case unpaired
    }

    public private(set) var phase: Phase
    /// What was shared, as shared.
    public let link: String?
    let client: CylindarrClient?

    public init(link: String?, pairing: Pairing?, session: URLSession = .shared) {
        self.link = link
        client = pairing.map { CylindarrClient(pairing: $0, session: session) }
        if pairing == nil {
            phase = .unpaired
        } else if link == nil {
            phase = .problem("There's no link in what was shared.")
        } else {
            phase = .sending
        }
    }

    public func send() async {
        guard let client, let link, phase == .sending || phase.isProblem else { return }
        phase = .sending
        do {
            phase = .answered(try await client.grab(link))
        } catch {
            phase = .problem(error.localizedDescription)
        }
    }

    public func follow() async {
        guard let client, case .answered(let answer) = phase, let offer = answer.follow else { return }
        phase = .following
        do {
            phase = .followed(try await client.follow(url: offer.url))
        } catch {
            phase = .problem(error.localizedDescription)
        }
    }

    /// Queued, or already there: nothing to decide, so the card goes.
    public var closesItself: Bool {
        switch phase {
        case .answered(let a): a.outcome == .queued || a.outcome == .already
        case .followed: true
        default: false
        }
    }

    public var canRetry: Bool { phase.isProblem && client != nil && link != nil }

    /// Its row on Cylindarr's pages, or the new subscription's page.
    public var pageURL: URL? {
        switch phase {
        case .answered(let a): a.grab.flatMap { client?.page($0.rowPath) }
        case .followed(let f): client?.page(f.pagePath)
        default: nil
        }
    }

    public var headline: String {
        switch phase {
        case .sending: "Sending to Cylindarr…"
        case .following: "Following…"
        case .unpaired: "Cylindarr isn't set up"
        case .problem: "Not grabbed"
        case .followed(let f): "Following \(f.name)"
        case .answered(let a):
            switch a.outcome {
            case .queued: "Grabbed"
            case .already: "Already there"
            case .followable: "Follow this?"
            case .refused: "Not grabbed"
            }
        }
    }

    public var message: String {
        switch phase {
        case .sending, .following: link ?? ""
        case .unpaired: "Open the Cylindarr app and pair it with your server from the server's settings page."
        case .problem(let why): why
        case .followed(let f): f.message
        case .answered(let a): a.message
        }
    }

    /// The video's title once the server knows it; the link before then.
    public var subject: String? {
        if case .answered(let a) = phase, let g = a.grab, g.state != .resolving { return g.title }
        return link
    }
}

extension GrabCard.Phase {
    var isProblem: Bool {
        if case .problem = self { return true }
        return false
    }
}

/// The link in whatever was shared: a URL, or text with one in it (the
/// YouTube app shares a URL; many apps share "Look at this: https://…").
public enum SharedLink {
    public static func find(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https", url.host() != nil { return trimmed }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return detector.matches(in: trimmed, range: range).compactMap(\.url)
            .first { $0.scheme == "http" || $0.scheme == "https" }?.absoluteString
    }
}
