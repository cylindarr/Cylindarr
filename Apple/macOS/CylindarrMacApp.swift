import AppKit
import CylindarrClientKit
import CylindarrClientUI
import SwiftUI

@main
struct CylindarrMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Grabs", id: "grabs") {
            MainView()
                .environment(AppModel.shared)
                .tint(.cylindarrAccent)
                .onOpenURL { AppModel.shared.open($0) }
        }
        .defaultSize(width: 560, height: 520)
        .commands { GrabCommands(model: AppModel.shared) }

        // One card at a time, whatever sent it: the Services menu, a
        // cylindarr://grab link or the Grab command.
        Window("Grab", id: "grab") {
            GrabWindow()
                .environment(AppModel.shared)
                .tint(.cylindarrAccent)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.top)

        Settings {
            MacSettings()
                .environment(AppModel.shared)
                .tint(.cylindarrAccent)
        }
    }
}

extension AppModel {
    /// The Services menu reaches the app through AppKit, outside any scene,
    /// so the app model is one instance it can find.
    static let shared = AppModel()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()
    }
}

/// Services ▸ Grab with Cylindarr, on a selected link or text with one in it.
final class ServiceProvider: NSObject {
    @MainActor @objc func grabWithCylindarr(_ pboard: NSPasteboard, userData: String?,
                                            error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let text = pboard.readObjects(forClasses: [NSURL.self])?.first.map { ($0 as! URL).absoluteString }
            ?? pboard.string(forType: .string) ?? ""
        guard SharedLink.find(in: text) != nil else {
            error.pointee = "There's no link in the selection." as NSString
            return
        }
        AppModel.shared.grab(text)
        NSApp.activate()
    }
}

/// The card's own small window. It opens when a card is set and closes
/// when the card goes.
struct GrabWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let card = model.card {
                GrabCardView(card: card, close: close, open: { openURL($0); close() })
                    .id(card.id)
            } else {
                Text("Nothing to grab.").padding(40).foregroundStyle(.secondary)
            }
        }
        .frame(width: 420)
    }

    func close() {
        model.card = nil
        dismissWindow(id: "grab")
    }
}

/// What the menu bar's commands act on: the focused window's list and its
/// selection.
struct WindowGrabs {
    let list: GrabList
    let selected: [Grab]
}

extension FocusedValues {
    @Entry var windowGrabs: WindowGrabs?
}

struct GrabCommands: Commands {
    let model: AppModel
    @FocusedValue(\.windowGrabs) private var focused
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Grab Link from Clipboard") {
                model.grab(NSPasteboard.general.string(forType: .string) ?? "")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(model.pairing == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Refresh") { if let list = focused?.list { Task { await list.refresh() } } }
                .keyboardShortcut("r")
                .disabled(focused == nil)
            Divider()
        }
        CommandMenu("Grab") {
            Button("Open Video Page") { for g in selected { open(g.sourceURL) } }
                .keyboardShortcut("o")
                .disabled(selected.isEmpty)
            Button("Show in Cylindarr") {
                for g in selected { if let url = focused?.list.client?.page(g.rowPath) { openURL(url) } }
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(selected.isEmpty)
            Divider()
            Button("Retry") {
                guard let list = focused?.list else { return }
                for g in selected where g.state.canRetry { Task { await list.retry(g) } }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!selected.contains { $0.state.canRetry })
        }
    }

    var selected: [Grab] { focused?.selected ?? [] }

    func open(_ link: String) {
        if let url = URL(string: link) { openURL(url) }
    }
}
