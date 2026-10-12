import AppIntents
import CylindarrClientKit

/// Grab with Cylindarr from Shortcuts, Spotlight, the Action button, or Back
/// Tap running a shortcut over a copied link.
struct GrabIntent: AppIntent {
    static let title: LocalizedStringResource = "Grab with Cylindarr"
    static let description = IntentDescription("Sends a video link to your Cylindarr server, which downloads it into Grabs.")

    @Parameter(title: "Link", inputConnectionBehavior: .connectToPreviousIntentResult)
    var link: String

    static var parameterSummary: some ParameterSummary {
        Summary("Grab \(\.$link) with Cylindarr")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let pairing = KeychainPairingStore().load() else {
            throw Problem.message("Cylindarr isn't paired with a server yet. Open the app to pair it.")
        }
        guard let found = SharedLink.find(in: link) else { throw Problem.message("There's no link in that.") }
        let answer = try await CylindarrClient(pairing: pairing).grab(found)
        if answer.outcome == .refused || answer.outcome == .followable { throw Problem.message(answer.message) }
        return .result(value: answer.message, dialog: IntentDialog(stringLiteral: answer.message))
    }

    enum Problem: Error, CustomLocalizedStringResourceConvertible {
        case message(String)
        var localizedStringResource: LocalizedStringResource {
            switch self { case .message(let m): "\(m)" }
        }
    }
}

struct CylindarrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GrabIntent(), phrases: ["Grab with \(.applicationName)"],
                    shortTitle: "Grab a Link", systemImageName: "arrow.down.circle")
    }
}
