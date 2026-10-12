import Foundation
import UniformTypeIdentifiers

extension SharedLink {
    /// The link in a share extension's input: a URL item if there is one
    /// (Safari, the YouTube app), otherwise the first link in shared text.
    @MainActor public static func load(from items: [NSExtensionItem]) async -> String? {
        let providers = items.flatMap { $0.attachments ?? [] }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               url.scheme == "http" || url.scheme == "https" {
                return url.absoluteString
            }
        }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let link = find(in: text) {
                return link
            }
        }
        // Some apps put the link in the item's text and attach nothing.
        for item in items {
            if let text = item.attributedContentText?.string, let link = find(in: text) { return link }
        }
        return nil
    }
}
