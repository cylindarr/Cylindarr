import CylindarrClientKit
import Foundation
import Observation

/// What the whole app shares: which server it is paired with, and a grab
/// waiting to be shown. Lists of grabs belong to each window, not to this.
@MainActor @Observable
final class AppModel {
    let store: PairingStore
    private(set) var pairing: Pairing?
    /// A pairing link opened from outside, waiting for a yes.
    var proposedPairing: Pairing?
    /// A grab from a link opened from outside, the Services menu or the
    /// Grab command, for the card to show.
    var card: GrabCard?

    init(store: PairingStore = KeychainPairingStore()) {
        self.store = store
        #if DEBUG
        // For simulator runs, which cannot tap the alert a pairing link raises.
        if let link = ProcessInfo.processInfo.environment["CYLINDARR_PAIR"], let p = Pairing(link: link) {
            try? store.save(p)
        }
        #endif
        pairing = store.load()
        #if DEBUG
        if let link = ProcessInfo.processInfo.environment["CYLINDARR_GRAB"] { grab(link) }
        #endif
    }

    var client: CylindarrClient? { pairing.map { CylindarrClient(pairing: $0) } }

    func paired(_ p: Pairing) {
        pairing = p
        proposedPairing = nil
    }

    func acceptProposedPairing() throws {
        guard let p = proposedPairing else { return }
        try store.save(p)
        paired(p)
    }

    func unpair() {
        store.clear()
        pairing = nil
    }

    func grab(_ text: String) {
        card = GrabCard(link: SharedLink.find(in: text), pairing: pairing)
    }

    /// `cylindarr://pair?url=…&key=…` from the settings page's code or link,
    /// and `cylindarr://grab?url=…` from anything that hands links over.
    func open(_ url: URL) {
        guard url.scheme == "cylindarr" else { return }
        switch url.host() {
        case "pair":
            // Asked, not done: a link on any web page could otherwise point
            // the app at someone else's server.
            proposedPairing = Pairing(link: url.absoluteString)
        case "grab":
            let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
            grab(link ?? "")
        default:
            break
        }
    }
}
