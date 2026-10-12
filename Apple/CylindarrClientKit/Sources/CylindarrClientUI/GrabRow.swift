import CylindarrClientKit
import SwiftUI

/// One grab in the app's list.
public struct GrabRow: View {
    let grab: Grab

    public init(_ grab: Grab) {
        self.grab = grab
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(grab.state == .resolving ? grab.host : grab.title)
                .font(.body.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 8) {
                StateBadge(grab.state)
                if !grab.summary.isEmpty {
                    Text(grab.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Text(grab.host + " · " + grab.added.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Pairing by hand: the server's address and key, or the pairing link
/// pasted whole. The link is the usual way; a camera reading the settings
/// page's code opens the app with it.
public struct PairingForm: View {
    @State private var address: String
    @State private var key: String
    @State private var checking = false
    @State private var problem: String?
    let store: PairingStore
    let paired: (Pairing) -> Void

    public init(store: PairingStore, current: Pairing? = nil, paired: @escaping (Pairing) -> Void) {
        self.store = store
        self.paired = paired
        _address = State(initialValue: current?.displayAddress ?? "")
        _key = State(initialValue: current?.key ?? "")
    }

    public var body: some View {
        Form {
            Section {
                TextField("Address", text: $address, prompt: Text("nas.local:8295"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                TextField("API key", text: $key, prompt: Text("From Cylindarr's settings page"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Server")
            } footer: {
                Text("Both are on Cylindarr's settings page under Connect an app. Pasting the pairing link fills them in.")
            }
            if let problem {
                Section { Text(problem).foregroundStyle(Color.cylindarr(.failed)) }
            }
            Section {
                Button("Paste Pairing Link", systemImage: "doc.on.clipboard", action: pasteLink)
                Button(action: { Task { await check() } }) {
                    HStack {
                        Text("Connect")
                        if checking { Spacer(); ProgressView() }
                    }
                }
                .disabled(Pairing(address: address, key: key) == nil || checking)
            }
        }
        .formStyle(.grouped)
    }

    func pasteLink() {
        #if os(iOS)
        let text = UIPasteboard.general.string ?? ""
        #else
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        #endif
        guard let p = Pairing(link: text) else {
            problem = "The clipboard doesn't hold a pairing link. Copy it from Cylindarr's settings page."
            return
        }
        address = p.displayAddress
        key = p.key
        Task { await check() }
    }

    func check() async {
        guard let pairing = Pairing(address: address, key: key) else { return }
        checking = true
        defer { checking = false }
        do {
            _ = try await CylindarrClient(pairing: pairing).status()
            try store.save(pairing)
            problem = nil
            paired(pairing)
        } catch {
            problem = error.localizedDescription
        }
    }
}
