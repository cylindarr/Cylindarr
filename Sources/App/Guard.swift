import Crypto
import CylindarrAPI
import Vapor

/// Who may use the pages. With `CYLINDARR_PASSWORD` set, every page asks
/// for it (HTTP Basic, which every browser and reverse proxy understands);
/// without it the network is the control, as it is for most arr apps on a
/// LAN. `/health` stays open for health checks and dashboards, and so do the
/// icons and style sheet, which FileMiddleware serves before this runs.
///
/// Whether or not a password is set, a form posted from another site is
/// refused: a browser holding the password would otherwise send it along
/// with any page's hidden form. Browsers mark such a request
/// `Sec-Fetch-Site: cross-site`, whatever host name a proxy gives the app.
///
/// The JSON API under `/api/` is neither: `APIKeyGuard` asks every call for
/// the key, which no other site's page can read, so a call from the browser
/// extension, which some browsers mark cross-site, is let through.
struct SiteGuard: AsyncMiddleware {
    let username: String
    let password: String?

    static func fromEnvironment() -> SiteGuard {
        let password = Environment.get("CYLINDARR_PASSWORD").flatMap { $0.isEmpty ? nil : $0 }
        let username = Environment.get("CYLINDARR_USERNAME").flatMap { $0.isEmpty ? nil : $0 } ?? "cylindarr"
        return SiteGuard(username: username, password: password)
    }

    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        if req.url.path.hasPrefix("/api/") { return try await next.respond(to: req) }
        if req.method != .GET, req.method != .HEAD, req.headers.first(name: "Sec-Fetch-Site") == "cross-site" {
            throw Abort(.forbidden, reason: "A form from another site cannot change Cylindarr.")
        }
        guard let password, req.url.path != "/health" else { return try await next.respond(to: req) }
        if let given = req.headers.basicAuthorization,
           Self.same(given.username, username), Self.same(given.password, password) {
            return try await next.respond(to: req)
        }
        let response = Response(status: .unauthorized)
        response.headers.replaceOrAdd(name: .wwwAuthenticate, value: #"Basic realm="Cylindarr", charset="UTF-8""#)
        return response
    }

    /// Compared as digests, whose equality takes the same time wherever
    /// the strings differ.
    static func same(_ a: String, _ b: String) -> Bool {
        SHA256.hash(data: Data(a.utf8)) == SHA256.hash(data: Data(b.utf8))
    }
}

/// The JSON API's only control: `X-Api-Key` must be the key on the settings
/// page. Checked against the settings as they are now, so a key made again
/// stops the old one at once.
struct APIKeyGuard: AsyncMiddleware {
    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let key = await req.application.engine.settings.apiKey
        guard !key.isEmpty, let given = req.headers.first(name: CylindarrAPI.keyHeader),
              SiteGuard.same(given, key) else {
            throw Abort(.unauthorized, reason: "Send the key from Cylindarr's settings page as \(CylindarrAPI.keyHeader).")
        }
        return try await next.respond(to: req)
    }
}
