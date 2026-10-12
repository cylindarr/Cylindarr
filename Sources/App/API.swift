import Fluent
import Vapor
import CylindarrAPI
import CylindarrKit

extension ServerStatus: @retroactive Content {}
extension Grab: @retroactive Content {}
extension GrabRequest: @retroactive Content {}
extension GrabResponse: @retroactive Content {}
extension FollowRequest: @retroactive Content {}
extension FollowResponse: @retroactive Content {}

/// The JSON API the apps and the browser extension use. Everything here is
/// also a page or a form; both call the same GrabService and
/// SubscriptionResolver, so the two cannot drift apart.
func apiRoutes(_ app: Application) {
    let api = app.grouped("api", "v1").grouped(APIKeyGuard())

    api.get("status") { req async throws -> ServerStatus in
        let status = await req.application.engine.status
        var pause: ServerStatus.Pause?
        if !status.gateOpen, let until = status.pausedUntil, let reason = status.reason {
            pause = .init(until: until, reason: reason.rawValue, sentence: Pages.pauseSentence(reason))
        }
        let waiting = try await FluentVideoStore(db: req.db).dueGrabs(at: Date(), limit: 1000).count
        return ServerStatus(version: cylindarrVersion, fetching: status.fetching, paused: pause,
                            grabsWaiting: waiting, current: status.current)
    }

    api.post("grabs") { req async throws -> Response in
        let body = try req.content.decode(GrabRequest.self)
        let answer = try await GrabService(req: req).grab(body.url)
        let status: HTTPStatus
        switch answer.outcome {
        case .queued: status = .accepted
        case .already: status = .ok
        case .followable, .refused: status = .unprocessableEntity
        }
        return try await answer.encodeResponse(status: status, for: req)
    }

    api.get("grabs") { req async throws -> [Grab] in
        let limit = min(max(req.query[Int.self, at: "limit"] ?? 50, 1), 200)
        return try await GrabService.recent(limit: limit, on: req)
    }

    api.get("grabs", ":key") { req async throws -> Grab in
        try await GrabService.dto(try await grabRecord(req), on: req)
    }

    api.post("grabs", ":key", "retry") { req async throws -> Grab in
        var r = try await grabRecord(req)
        r.state = .wanted
        r.attempts = 0
        try await FluentVideoStore(db: req.db).save(r)
        req.application.journal.record(Entry(verb: .want, noun: .grab, subject: r.id, outcome: .wanted, detail: "retried from an app"))
        await req.application.engine.wakeFetch()
        if VideoKey.isUnresolved(r.id) {
            let engine = req.application.engine
            let key = r.id
            Task { await engine.resolve(key) }
        }
        return try await GrabService.dto(r, on: req)
    }

    api.post("subscriptions") { req async throws -> Response in
        let body = try req.content.decode(FollowRequest.self)
        do {
            let sub = try await SubscriptionResolver(req: req).create(from: body.url, name: body.name, backfill: false, grabList: false)
            return try await FollowResponse(id: sub.id.uuidString, name: sub.name, message: "Following \(sub.name), from 30 days ago.",
                                            pagePath: "/subscriptions/\(sub.id.uuidString)")
                .encodeResponse(status: .created, for: req)
        } catch let e as SubscriptionResolver.Failure {
            throw Abort(.unprocessableEntity, reason: e.message)
        }
    }
}

/// A grab by its key. A provisional key that Resolve has since replaced is
/// found by the URL it was made from, so an app holding the old key still
/// gets the grab.
private func grabRecord(_ req: Request) async throws -> VideoRecord {
    guard let key = req.parameters.get("key") else { throw Abort(.badRequest) }
    if let m = try await VideoModel.find(key, on: req.db) { return m.record }
    if VideoKey.isUnresolved(key) {
        for m in try await VideoModel.query(on: req.db).filter(\.$sourceURL != nil).sort(\.$firstSeen, .descending).limit(500).all()
        where GrabService.hash(m.sourceURL!) == String(key.dropFirst(VideoKey.unresolvedPrefix.count)) {
            return m.record
        }
    }
    throw Abort(.notFound, reason: "No grab \(key).")
}
