import CylindarrClientKit
import CylindarrClientUI
import SwiftUI

@main
struct CylindarrApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.cylindarrAccent)
                .onOpenURL { model.open($0) }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let pairing = model.pairing {
                GrabsScreen(client: CylindarrClient(pairing: pairing))
                    .id(pairing)
            } else {
                WelcomeScreen()
            }
        }
        .sheet(item: $model.card) { card in
            GrabCardView(card: card, close: { model.card = nil }, open: { UIApplication.shared.open($0) })
                .presentationDetents([.height(230)])
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

struct WelcomeScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    CylindarrMark().frame(width: 72, height: 72)
                    Text("Pair with your Cylindarr").font(.title2.bold())
                    Text("On your server's settings page, under Connect an app, scan the code with the Camera app. Or enter the address and key here.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
                PairingForm(store: model.store) { model.paired($0) }
            }
            .navigationTitle("Cylindarr")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct GrabsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var list: GrabList
    @State private var showingSettings = false

    init(client: CylindarrClient) {
        _list = State(initialValue: GrabList(client: client))
    }

    var body: some View {
        NavigationStack {
            List {
                if let note = list.pauseNote {
                    Label(note, systemImage: "pause.circle").font(.callout).foregroundStyle(.secondary)
                }
                if let problem = list.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Color.cylindarr(.failed))
                }
                ForEach(list.grabs) { grab in
                    Button { open(grab.sourceURL) } label: { GrabRow(grab) }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: grab) }
                        .swipeActions {
                            if grab.state.canRetry {
                                Button("Retry", systemImage: "arrow.clockwise") { Task { await list.retry(grab) } }
                                    .tint(.cylindarrAccent)
                            }
                        }
                }
            }
            .overlay {
                if list.grabs.isEmpty, list.lastLoaded != nil {
                    ContentUnavailableView("No Grabs Yet", systemImage: "arrow.down.circle",
                                           description: Text("Share a video from Safari, YouTube or any app, and choose Grab with Cylindarr."))
                }
            }
            .navigationTitle("Grabs")
            .refreshable { await list.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gear") { showingSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PasteButton(payloadType: String.self) { strings in
                        if let text = strings.first { model.grab(text) }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Grab the link on the clipboard")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsScreen() }
        }
        // While the app is in front: now, and every few seconds while
        // something is on its way.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await list.refresh()
                try? await Task.sleep(for: .seconds(list.isMoving ? 4 : 30))
            }
        }
        .onChange(of: model.card == nil) { _, closed in
            if closed { Task { await list.refresh() } }
        }
    }

    @ViewBuilder func menu(for grab: Grab) -> some View {
        Button("Open Video Page", systemImage: "safari") { open(grab.sourceURL) }
        if let page = list.client?.page(grab.rowPath) {
            Button("Show in Cylindarr", systemImage: "list.bullet.rectangle") { openURL(page) }
        }
        Button("Copy Link", systemImage: "doc.on.doc") { UIPasteboard.general.string = grab.sourceURL }
        if grab.state.canRetry {
            Button("Retry", systemImage: "arrow.clockwise") { Task { await list.retry(grab) } }
        }
    }

    func open(_ link: String) {
        if let url = URL(string: link) { openURL(url) }
    }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingUnpair = false

    var body: some View {
        NavigationStack {
            Form {
                if let p = model.pairing {
                    Section {
                        LabeledContent("Address", value: p.displayAddress)
                        NavigationLink("Change Server") {
                            PairingForm(store: model.store, current: p) { model.paired($0); dismiss() }
                                .navigationTitle("Server")
                        }
                        Button("Unpair", role: .destructive) { confirmingUnpair = true }
                    } header: {
                        Text("Server")
                    } footer: {
                        Text("Share a video and choose Grab with Cylindarr. If it isn't in the share sheet, scroll the app row to the end, tap More, and turn it on.")
                    }
                }
                Section {
                    Link("Cylindarr's Pages", destination: model.pairing?.server ?? URL(string: "https://github.com")!)
                } footer: {
                    AppVersion().padding(.top, 24)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Unpair from this server?", isPresented: $confirmingUnpair, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) { model.unpair(); dismiss() }
            } message: {
                Text("The share sheet stops working until the app is paired again.")
            }
        }
    }
}
