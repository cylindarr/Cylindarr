import AppKit
import CylindarrClientKit
import CylindarrClientUI
import SwiftUI

/// Share ▸ Grab with Cylindarr, from any app's share menu.
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { @MainActor in
            let link = await SharedLink.load(from: items)
            let card = GrabCard(link: link, pairing: KeychainPairingStore().load())
            let host = NSHostingView(rootView: GrabCardView(card: card, close: { [weak self] in self?.finish() },
                                                            open: { [weak self] url in NSWorkspace.shared.open(url); self?.finish() })
                .tint(.cylindarrAccent))
            host.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.topAnchor.constraint(equalTo: view.topAnchor),
                host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            preferredContentSize = host.fittingSize
        }
    }

    func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
