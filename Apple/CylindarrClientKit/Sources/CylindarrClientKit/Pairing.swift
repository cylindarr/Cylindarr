@_exported import CylindarrAPI
import Foundation
import Security

/// Which server the apps grab with, and its key. One pairing for the app and
/// all its extensions, held in the Keychain under a shared access group so
/// the share sheet and Shortcuts read what the app saved.
public struct Pairing: Codable, Sendable, Hashable {
    public var server: URL
    public var key: String

    public init(server: URL, key: String) {
        self.server = server
        self.key = key
    }

    /// From `cylindarr://pair?url=…&key=…`, as the settings page shows it.
    public init?(link: String) {
        guard let parsed = CylindarrAPI.parsePairingLink(link) else { return nil }
        self.init(server: parsed.server, key: parsed.key)
    }

    /// From an address typed by hand: `nas.local:8295` means `http://nas.local:8295`.
    public init?(address: String, key: String) {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if !text.contains("://") { text = "http://" + text }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "http" || url.scheme == "https", url.host() != nil, !key.isEmpty else {
            return nil
        }
        self.init(server: url, key: key)
    }

    /// The server's address as a person would write it.
    public var displayAddress: String {
        server.absoluteString.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
    }
}

public protocol PairingStore: Sendable {
    func load() -> Pairing?
    func save(_ pairing: Pairing) throws
    func clear()
}

public struct KeychainError: LocalizedError, Equatable {
    public let status: OSStatus
    public var errorDescription: String? {
        "The Keychain refused to save the pairing (\(SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"))."
    }
}

public struct KeychainPairingStore: PairingStore {
    /// `$(AppIdentifierPrefix)com.pantuso.cylindarr`, read from the
    /// `CylindarrKeychainGroup` Info.plist key every target sets, so a build
    /// under another team needs no code change.
    public let accessGroup: String?
    static let service = "com.pantuso.cylindarr.pairing"

    public init(accessGroup: String? = Bundle.main.object(forInfoDictionaryKey: "CylindarrKeychainGroup") as? String) {
        self.accessGroup = accessGroup
    }

    var query: [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: "server",
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    public func load() -> Pairing? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }

    public func save(_ pairing: Pairing) throws {
        clear()
        var q = query
        q[kSecValueData as String] = try JSONEncoder().encode(pairing)
        // After first unlock, so a share from a locked phone's widget still reads it.
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// For previews and tests.
public final class MemoryPairingStore: PairingStore, @unchecked Sendable {
    private var pairing: Pairing?
    private let lock = NSLock()
    public init(_ pairing: Pairing? = nil) { self.pairing = pairing }
    public func load() -> Pairing? { lock.withLock { pairing } }
    public func save(_ pairing: Pairing) throws { lock.withLock { self.pairing = pairing } }
    public func clear() { lock.withLock { pairing = nil } }
}
