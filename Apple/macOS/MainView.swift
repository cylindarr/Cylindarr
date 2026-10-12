import AppKit
import CylindarrClientKit
import CylindarrClientUI
import SwiftUI

/// A window of grabs. Each window keeps its own list and selection, so two
/// windows never fight over what is selected.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let pairing = model.pairing {
                GrabsList(client: CylindarrClient(pairing: pairing))
                    .id(pairing)
            } else {
                VStack(spacing: 12) {
                    CylindarrMark().frame(width: 64, height: 64)
                    Text("Pair with your Cylindarr").font(.title2.bold())
                    Text("Open the pairing link from your server's settings page, under Connect an app, or enter its address and key.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
                    PairingForm(store: model.store) { model.paired($0) }
                        .frame(maxWidth: 440, maxHeight: 300)
                }
                .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .onChange(of: model.card?.id) { _, id in
            if id != nil { openWindow(id: "grab") }
        }
        .alert("Pair with this server?", isPresented: Binding(get: { model.proposedPairing != nil }, set: { if !$0 { model.proposedPairing = nil } }),
               presenting: model.proposedPairing) { _ in
            Button("Pair") { try? model.acceptProposedPairing() }
            Button("Cancel", role: .cancel) { model.proposedPairing = nil }
        } message: { p in
            Text("Grabs will go to \(p.displayAddress).")
        }
    }
}

struct GrabsList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.controlActiveState) private var active
    @State private var list: GrabList
    @State private var selection = Set<String>()

    init(client: CylindarrClient) {
        _list = State(initialValue: GrabList(client: client))
    }

    var selected: [Grab] { list.grabs.filter { selection.contains($0.key) } }

    var body: some View {
        List(selection: $selection) {
            if let note = list.pauseNote {
                Label(note, systemImage: "pause.circle").foregroundStyle(.secondary)
            }
            if let problem = list.problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Color.cylindarr(.failed))
            }
            ForEach(list.grabs) { grab in
                GrabRow(grab)
                    .tag(grab.key)
                    .draggable(URL(string: grab.sourceURL) ?? URL(string: "about:blank")!)
                    .help(grab.sourceURL)
            }
        }
        .contextMenu(forSelectionType: String.self) { keys in
            let grabs = list.grabs.filter { keys.contains($0.key) }
            Button("Open Video Page") { grabs.forEach { open($0.sourceURL) } }
            Button("Show in Cylindarr") { grabs.forEach { g in list.client?.page(g.rowPath).map { openURL($0) } } }
            Button("Copy Link") { copy(grabs) }
            if grabs.contains(where: { $0.state.canRetry }) {
                Divider()
                Button("Retry") { for g in grabs where g.state.canRetry { Task { await list.retry(g) } } }
            }
        } primaryAction: { keys in
            list.grabs.filter { keys.contains($0.key) }.forEach { open($0.sourceURL) }
        }
        .copyable(selected.compactMap { URL(string: $0.sourceURL) })
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.grab(url.absoluteString)
            return true
        }
        .overlay {
            if list.grabs.isEmpty, list.lastLoaded != nil {
                ContentUnavailableView("No Grabs Yet", systemImage: "arrow.down.circle",
                                       description: Text("Share a video from any app, use Services ▸ Grab with Cylindarr, or drop a link here."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Grab Link from Clipboard", systemImage: "doc.on.clipboard") {
                    model.grab(NSPasteboard.general.string(forType: .string) ?? "")
                }
                .help("Grab the link on the clipboard (⇧⌘V)")
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await list.refresh() } }
                    .help("Refresh (⌘R)")
            }
        }
        .navigationTitle("Grabs")
        .navigationSubtitle(model.pairing?.displayAddress ?? "")
        .focusedSceneValue(\.windowGrabs, WindowGrabs(list: list, selected: selected))
        // Refreshed while the window is in front: often while something is
        // on its way, rarely otherwise.
        .task(id: active) {
            guard active != .inactive else { return }
            while !Task.isCancelled {
                await list.refresh()
                try? await Task.sleep(for: .seconds(list.isMoving ? 4 : 30))
            }
        }
        .onChange(of: model.card == nil) { _, closed in
            if closed { Task { await list.refresh() } }
        }
    }

    func open(_ link: String) {
        if let url = URL(string: link) { openURL(url) }
    }

    func copy(_ grabs: [Grab]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(grabs.compactMap { URL(string: $0.sourceURL) as NSURL? })
    }
}

struct MacSettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingUnpair = false

    var body: some View {
        VStack(spacing: 0) {
            PairingForm(store: model.store, current: model.pairing) { model.paired($0) }
                .id(model.pairing)
            HStack {
                if model.pairing != nil {
                    Button("Unpair…") { confirmingUnpair = true }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            AppVersion().padding(.vertical, 12)
        }
        .frame(width: 460)
        .confirmationDialog("Unpair from this server?", isPresented: $confirmingUnpair) {
            Button("Unpair", role: .destructive) { model.unpair() }
        } message: {
            Text("The share menu and Services stop working until the app is paired again.")
        }
    }
}
