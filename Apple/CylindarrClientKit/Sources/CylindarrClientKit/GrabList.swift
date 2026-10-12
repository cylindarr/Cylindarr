import Foundation
import Observation

/// The app's window onto the server: recent grabs and whether fetching is
/// held. Refreshed when the app comes forward and every few seconds while a
/// grab is moving, never in the background.
@MainActor @Observable
public final class GrabList {
    public private(set) var grabs: [Grab] = []
    public private(set) var status: ServerStatus?
    public private(set) var problem: String?
    public private(set) var loading = false
    public private(set) var lastLoaded: Date?
    public var client: CylindarrClient?

    public init(client: CylindarrClient?) {
        self.client = client
    }

    public func refresh() async {
        guard let client else { return }
        loading = true
        defer { loading = false }
        do {
            async let s = client.status()
            async let g = client.grabs()
            (status, grabs) = try await (s, g)
            problem = nil
            lastLoaded = Date()
        } catch {
            problem = error.localizedDescription
        }
    }

    public func retry(_ grab: Grab) async {
        guard let client else { return }
        do {
            let updated = try await client.retry(grab.key)
            if let i = grabs.firstIndex(where: { $0.key == grab.key }) { grabs[i] = updated }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Something is still on its way, so the list is worth refreshing soon.
    public var isMoving: Bool {
        grabs.contains { [.resolving, .wanted, .fetching].contains($0.state) }
    }

    /// Why YouTube downloads are held, in a sentence, when they are.
    public var pauseNote: String? {
        guard let status else { return nil }
        if !status.fetching { return "Fetching is switched off in Cylindarr's settings." }
        guard let p = status.paused else { return nil }
        return "YouTube downloads are paused until \(p.until.formatted(date: .omitted, time: .shortened)): \(p.sentence) Grabs from other sites go on."
    }
}

extension Grab.State {
    /// The words the pages use for each state.
    public var label: String {
        switch self {
        case .resolving: "Looking"
        case .wanted: "In line"
        case .fetching: "Downloading"
        case .deferred: "Waiting to retry"
        case .failed: "Needs you"
        case .placed: "In the library"
        case .skipped: "Skipped"
        case .retired: "Retired"
        }
    }

    public var symbol: String {
        switch self {
        case .resolving: "magnifyingglass"
        case .wanted: "clock"
        case .fetching: "arrow.down.circle"
        case .deferred: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle"
        case .placed: "checkmark.circle"
        case .skipped: "minus.circle"
        case .retired: "archivebox"
        }
    }

    public var canRetry: Bool { self == .failed || self == .deferred || self == .skipped }
}

extension Grab {
    /// The line under the title in the list.
    public var summary: String {
        switch state {
        case .wanted, .resolving: position.map { $0 == 1 ? "Next" : "\($0) in line" } ?? ""
        case .deferred:
            [cause, nextAttempt.map { "next try " + $0.formatted(date: .omitted, time: .shortened) }].compactMap(\.self).joined(separator: ", ")
        case .failed, .skipped: detail ?? cause ?? ""
        default: ""
        }
    }

    /// The site, for a grab whose title is not known yet.
    public var host: String { URL(string: sourceURL)?.host() ?? sourceURL }
}
