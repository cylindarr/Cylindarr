import CylindarrClientKit
import CylindarrClientUI
import SwiftUI
import UIKit

/// Share, then Grab with Cylindarr: the link goes to the server at once and
/// the card says what happened, then closes itself.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { @MainActor in
            let link = await SharedLink.load(from: items)
            let card = GrabCard(link: link, pairing: KeychainPairingStore().load())
            let host = UIHostingController(rootView: GrabCardView(card: card, close: { [weak self] in self?.finish() },
                                                                  open: { [weak self] url in self?.open(url) }))
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            ])
            host.didMove(toParent: self)
        }
    }

    func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// An extension can't open URLs itself; the responder chain reaches the
    /// host app's UIApplication, which can.
    func open(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url)
                break
            }
            responder = r.next
        }
        finish()
    }
}
