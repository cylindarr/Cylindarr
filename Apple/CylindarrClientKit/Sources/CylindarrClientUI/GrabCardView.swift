import CylindarrClientKit
import SwiftUI

/// The card a share shows. It sends at once, says what happened, and closes
/// itself a moment after a grab is queued; a question or a problem waits for
/// a tap.
public struct GrabCardView: View {
    @Bindable var card: GrabCard
    let close: () -> Void
    let open: (URL) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long a queued grab's card stays before closing itself.
    static let linger: Duration = .milliseconds(1500)

    public init(card: GrabCard, close: @escaping () -> Void, open: @escaping (URL) -> Void) {
        self.card = card
        self.close = close
        self.open = open
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CylindarrMark()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(card.headline).font(.headline)
                        indicator
                    }
                    if let subject = card.subject, subject != card.message {
                        Text(subject).font(.subheadline.weight(.medium)).lineLimit(2)
                    }
                    Text(card.message).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            buttons
        }
        .padding(18)
        .frame(maxWidth: 440, alignment: .leading)
        .tint(.cylindarrAccent)
        .task(id: card.phase) {
            if card.phase == .sending { await card.send() }
            if card.closesItself {
                try? await Task.sleep(for: Self.linger)
                if !Task.isCancelled { close() }
            }
        }
        .animation(reduceMotion ? nil : .default, value: card.phase)
    }

    @ViewBuilder var indicator: some View {
        switch card.phase {
        case .sending, .following: ProgressView().controlSize(.small)
        case .answered(let a) where a.outcome == .queued || a.outcome == .already:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.cylindarr(.placed)).accessibilityHidden(true)
        case .answered(let a) where a.outcome == .followable:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(Color.cylindarrAccent).accessibilityHidden(true)
        case .followed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.cylindarr(.placed)).accessibilityHidden(true)
        case .problem, .unpaired, .answered:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.cylindarr(.failed)).accessibilityHidden(true)
        }
    }

    @ViewBuilder var buttons: some View {
        HStack {
            if card.canRetry {
                Button("Try Again") { Task { await card.send() } }
            }
            if case .answered(let a) = card.phase, a.outcome == .followable {
                Button("Follow") { Task { await card.follow() } }
                    .buttonStyle(.borderedProminent)
            }
            if let page = card.pageURL {
                Button("Open in Cylindarr") { open(page) }
            }
            Spacer()
            Button(card.closesItself ? "Done" : "Close", action: close)
                .keyboardShortcut(.cancelAction)
        }
        .controlSize(.regular)
    }
}

#Preview("Queued") {
    GrabCardView(card: GrabCard(link: "https://www.youtube.com/watch?v=snyvQ9COmb8", pairing: nil), close: {}, open: { _ in })
}
