import Fluent
import FluentSQLiteDriver
import Leaf
import Vapor
import CylindarrKit

let cylindarrVersion = "0.2.0"

public func configure(_ app: Application) async throws {
    let data = Environment.get("CYLINDARR_DATA") ?? app.directory.workingDirectory + "data"
    try FileManager.default.createDirectory(atPath: data, withIntermediateDirectories: true)

    app.databases.use(.sqlite(.file(data + "/cylindarr.sqlite")), as: .sqlite)
    Migrations.register(app)
    try await app.autoMigrate()

    app.views.use(.leaf)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    let guardian = SiteGuard.fromEnvironment()
    app.middleware.use(guardian)
    app.routes.defaultMaxBodySize = "1mb"

    let journal = StdoutJournal(db: app.db)
    app.storage[JournalKey.self] = journal
    let settings = await AppSettings.load(app.db)
    app.storage[EngineKey.self] = Engine(app: app, journal: journal, dataDirectory: data, settings: settings)
    app.lifecycle.use(EngineLifecycle())
    try routes(app)

    journal.record(Entry(verb: .configure, noun: .system, subject: "startup", outcome: .ok,
                         detail: "version=\(cylindarrVersion) library=\(settings.libraryRoot) yt-dlp=\(settings.ytdlpPath) pot=\(settings.potProvider.isEmpty ? "off" : settings.potProvider) proxy=\(settings.proxy.isEmpty ? "direct" : Entry.redactCookies(in: settings.proxy)) encoder=\(settings.encoder) password=\(guardian.password == nil ? "off" : "on") data=\(data)"))
}
