import Foundation

/// The server's JSON API, one call per method. Short timeouts throughout: a
/// share extension that waits on a server that isn't there is killed by the
/// system, and a person holding a phone gives up sooner than that.
public struct CylindarrClient: Sendable {
    public let pairing: Pairing
    let session: URLSession
    let timeout: TimeInterval

    public init(pairing: Pairing, session: URLSession = .shared, timeout: TimeInterval = 10) {
        self.pairing = pairing
        self.session = session
        self.timeout = timeout
    }

    public enum Failure: LocalizedError, Equatable {
        case unreachable(String)
        case badKey
        case server(Int, String)
        case unreadable

        public var errorDescription: String? {
            switch self {
            case .unreachable(let why): "Couldn't reach Cylindarr: \(why)"
            case .badKey: "Cylindarr didn't accept the key. Pair again from its settings page."
            case .server(_, let reason): reason
            case .unreadable: "Cylindarr answered with something this app can't read. The server and the app may be different versions."
            }
        }
    }

    public func status() async throws -> ServerStatus {
        try await call("GET", "status")
    }

    /// Any answer the server gives about a link comes back as a
    /// GrabResponse, refusals included; only a failure to talk throws.
    public func grab(_ url: String) async throws -> GrabResponse {
        try await call("POST", "grabs", body: try encode(GrabRequest(url: url)), acceptingErrors: true)
    }

    public func grabs(limit: Int = 50) async throws -> [Grab] {
        try await call("GET", "grabs", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    public func retry(_ key: String) async throws -> Grab {
        try await call("POST", "grabs/\(key)/retry")
    }

    public func follow(url: String, name: String? = nil) async throws -> FollowResponse {
        try await call("POST", "subscriptions", body: try encode(FollowRequest(url: url, name: name)))
    }

    /// A page on the server, from a path the API gave (a grab's row).
    public func page(_ path: String) -> URL? {
        URL(string: path, relativeTo: pairing.server)?.absoluteURL
    }

    func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        var url = pairing.server.appending(path: String(CylindarrAPI.pathPrefix.dropFirst())).appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue(pairing.key, forHTTPHeaderField: CylindarrAPI.keyHeader)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    func encode(_ value: some Encodable) throws -> Data { try CylindarrAPI.encoder().encode(value) }

    func call<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
                            acceptingErrors: Bool = false) async throws -> T {
        let (bytes, response): (Data, URLResponse)
        do {
            (bytes, response) = try await session.data(for: request(method, path, query: query, body: body))
        } catch let e as URLError {
            throw Failure.unreachable(Self.describe(e))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoder = CylindarrAPI.decoder()
        if (200..<300).contains(status) || acceptingErrors, let value = try? decoder.decode(T.self, from: bytes) {
            return value
        }
        if status == 401 { throw Failure.badKey }
        if let e = try? decoder.decode(APIErrorBody.self, from: bytes) { throw Failure.server(status, e.reason) }
        if (200..<300).contains(status) { throw Failure.unreadable }
        throw Failure.server(status, HTTPURLResponse.localizedString(forStatusCode: status).capitalized + " (\(status)).")
    }

    static func describe(_ e: URLError) -> String {
        switch e.code {
        case .timedOut: "it didn't answer in time."
        case .cannotFindHost, .dnsLookupFailed: "no server by that name. If it is on a VPN such as Tailscale, is that connected?"
        case .cannotConnectToHost: "nothing is listening at that address."
        case .notConnectedToInternet: "this device is offline."
        case .appTransportSecurityRequiresSecureConnection: "this build only allows https."
        default: e.localizedDescription
        }
    }
}
