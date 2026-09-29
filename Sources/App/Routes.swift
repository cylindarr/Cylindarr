import Fluent
import Vapor
import CylindarrKit

func routes(_ app: Application) throws {
    adoptRoutes(app)
    app.get("health") { req async -> Response in
        let body = #"{"status":"ok","version":"\#(cylindarrVersion)"}"#
        return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(string: body))
    }

    app.get { req async throws -> View in
        try await req.view.render("index", try await Pages.overview(req))
    }

    app.get("subscriptions") { req async throws -> View in
        try await req.view.render("subscriptions", try await Pages.subscriptions(req))
    }

    app.post("subscriptions") { req async throws -> Response in
        struct Form: Content {
            var url: String
            var name: String?
            var backfill: String?
            var grabList: String?
        }
        let form = try req.content.decode(Form.self)
        do {
            let sub = try await SubscriptionResolver(req: req).create(
                from: form.url, name: form.name, backfill: form.backfill == "on", grabList: form.grabList == "on")
            return req.redirect(to: "/subscriptions/\(sub.id)")
        } catch let e as SubscriptionResolver.Failure {
            return req.redirect(to: "/subscriptions?error=" + (e.message.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))
        }
    }

    app.get("subscriptions", ":id") { req async throws -> View in
        try await req.view.render("subscription", try await Pages.subscription(req))
    }

    app.post("subscriptions", ":id") { req async throws -> Response in
        guard let model = try await SubscriptionModel.find(req.parameters.get("id", as: UUID.self), on: req.db) else { throw Abort(.notFound) }
        var sub = model.domain
        try RuleForm.apply(try req.content.decode(RuleForm.self), to: &sub)
        model.update(from: sub)
        try await model.update(on: req.db)
        req.application.journal.record(Entry(verb: .configure, noun: .subscription, subject: sub.name, outcome: .ok, detail: "rules changed"))
        await req.application.engine.exportSubscriptions()
        await req.application.engine.reconsider(sub.id)
        await req.application.engine.retireByRule(sub.id)
        return req.redirect(to: "/subscriptions/\(sub.id)")
    }

    app.post("subscriptions", ":id", "poll") { req async throws -> Response in
        guard let model = try await SubscriptionModel.find(req.parameters.get("id", as: UUID.self), on: req.db) else { throw Abort(.notFound) }
        await req.application.engine.poll(model)
        return req.redirect(to: "/subscriptions/\(model.id!)")
    }

    app.post("subscriptions", ":id", "enumerate") { req async throws -> Response in
        guard let model = try await SubscriptionModel.find(req.parameters.get("id", as: UUID.self), on: req.db) else { throw Abort(.notFound) }
        let engine = req.application.engine
        Task { await engine.enumerate(model) }
        return req.redirect(to: "/subscriptions/\(model.id!)")
    }

    /// Forgets the subscription and its decisions. Files already placed stay:
    /// the files are the library, and removing a show from disk is a person's call.
    app.post("subscriptions", ":id", "delete") { req async throws -> Response in
        guard let model = try await SubscriptionModel.find(req.parameters.get("id", as: UUID.self), on: req.db) else { throw Abort(.notFound) }
        try await VideoModel.query(on: req.db).filter(\.$subscriptionID == model.id!).filter(\.$state != "placed").delete()
        req.application.journal.record(Entry(verb: .purge, noun: .subscription, subject: model.name, outcome: .ok, detail: "unfollowed; placed files kept"))
        try await model.delete(on: req.db)
        await req.application.engine.exportSubscriptions()
        return req.redirect(to: "/subscriptions")
    }

    app.post("subscriptions", ":id", "keep") { req async throws -> Response in
        struct Form: Content { var from: String }
        guard let id = req.parameters.get("id", as: UUID.self),
              let from = Pages.day.date(from: try req.content.decode(Form.self).from) else { throw Abort(.badRequest) }
        _ = await req.application.engine.keepOnly(from: from, subscription: id)
        return req.redirect(to: "/subscriptions/\(id)")
    }

    app.post("grab") { req async throws -> Response in
        struct Form: Content { var url: String }
        let form = try req.content.decode(Form.self)
        do {
            let id = try await SubscriptionResolver(req: req).grab(form.url)
            return req.redirect(to: "/?grabbed=\(id)")
        } catch let e as SubscriptionResolver.Failure {
            return req.redirect(to: "/?error=" + (e.message.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))
        }
    }

    app.post("videos", ":id", ":action") { req async throws -> Response in
        guard let model = try await VideoModel.find(req.parameters.get("id"), on: req.db) else { throw Abort(.notFound) }
        var r = model.record
        switch req.parameters.get("action") {
        case "retry", "want":
            r.state = .wanted
            r.attempts = 0
        case "skip":
            r.state = .skipped(.byHand)
        default:
            throw Abort(.badRequest)
        }
        model.apply(r)
        try await model.update(on: req.db)
        req.application.journal.record(Entry(verb: r.state == .wanted ? .want : .skip, noun: .video, subject: r.id,
                                             outcome: r.state == .wanted ? .wanted : .skipped, detail: "by hand: \(r.title)"))
        return req.redirect(to: req.headers.first(name: .referer) ?? "/")
    }

    app.post("library", "again") { req async -> Response in
        _ = await req.application.engine.downloadLibraryAgain()
        return req.redirect(to: "/")
    }

    app.post("queue", "resume") { req async -> Response in
        await req.application.engine.resume()
        return req.redirect(to: "/")
    }

    app.post("access", "verify") { req async -> Response in
        _ = await req.application.engine.verifyNow()
        return req.redirect(to: "/")
    }

    app.post("access", "update") { req async -> Response in
        await req.application.engine.updateYtDlp(force: true)
        return req.redirect(to: "/")
    }

    app.post("poll") { req async -> Response in
        await req.application.engine.requestPoll()
        return req.redirect(to: "/")
    }

    app.get("settings") { req async throws -> View in
        try await req.view.render("settings", try await Pages.settings(req))
    }

    app.post("settings") { req async throws -> Response in
        var s = await AppSettings.load(req.db)
        try SettingsForm.apply(try req.content.decode(SettingsForm.self), to: &s)
        try await s.save(req.db)
        await req.application.engine.reload()
        req.application.journal.record(Entry(verb: .configure, noun: .system, subject: "settings", outcome: .ok))
        return req.redirect(to: "/settings")
    }

    app.post("settings", "encoding") { req async throws -> Response in
        struct Form: Content { var encoder: String; var encodeQuality: String }
        let form = try req.content.decode(Form.self)
        var s = await AppSettings.load(req.db)
        if AppSettings.encoderChoices.contains(form.encoder) { s.encoder = form.encoder }
        if let q = Int(form.encodeQuality) { s.encodeQuality = min(max(q, 10), 40) }
        try await s.save(req.db)
        await req.application.engine.reload()
        req.application.journal.record(Entry(verb: .configure, noun: .system, subject: "encoding", outcome: .ok,
                                             detail: "\(s.encoder), quality \(s.encodeQuality)"))
        return req.redirect(to: "/settings")
    }

    // A whole-browser export can run to megabytes; only YouTube's and
    // Google's cookies are kept.
    app.on(.POST, "settings", "cookies", body: .collect(maxSize: "10mb")) { req async throws -> Response in
        struct Form: Content { var cookies: File? }
        func refuse(_ why: String) -> Response {
            req.redirect(to: "/settings?error=" + (why.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))
        }
        guard let file = try req.content.decode(Form.self).cookies, file.data.readableBytes > 0 else {
            return refuse("Choose a cookies.txt file to upload.")
        }
        guard let text = file.data.getString(at: file.data.readerIndex, length: file.data.readableBytes) else {
            return refuse("That file is not text, so it is not a cookies.txt.")
        }
        let problems = CookieJar.parse(text).problems(at: Date())
        guard problems.isEmpty else { return refuse("Not saved: " + Pages.describe(problems) + ".") }
        let kept = CookieJar.youtubeOnly(text)
        let path = await req.application.engine.dataDirectory + "/cookies.txt"
        FileManager.default.createFile(atPath: path, contents: Data(kept.utf8), attributes: [.posixPermissions: 0o600])
        req.application.journal.record(Entry(verb: .configure, noun: .access, subject: "cookies", outcome: .ok,
                                             detail: "\(CookieJar.parse(kept).cookies.count) YouTube cookies"))
        // A signed-in request now, so the page says whether the session is
        // live instead of waiting for the hourly check.
        _ = await req.application.engine.verifyNow()
        return req.redirect(to: "/settings")
    }

    app.post("settings", "cookies", "remove") { req async throws -> Response in
        let path = await req.application.engine.dataDirectory + "/cookies.txt"
        try? FileManager.default.removeItem(atPath: path)
        req.application.journal.record(Entry(verb: .configure, noun: .access, subject: "cookies", outcome: .ok, detail: "removed"))
        _ = await req.application.engine.verifyNow()
        return req.redirect(to: "/settings")
    }

    app.get("journal") { req async throws -> View in
        try await req.view.render("journal", try await Pages.journal(req))
    }
}
