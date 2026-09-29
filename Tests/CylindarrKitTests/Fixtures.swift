import Foundation

enum Fixture {
    static func url(_ path: String) -> URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent(path)
    }

    static func data(_ path: String) -> Data {
        try! Data(contentsOf: url(path))
    }

    static func text(_ path: String) -> String {
        String(decoding: data(path), as: UTF8.self)
    }

    static func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: iso)!
    }
}
