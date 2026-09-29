import Foundation
import CylindarrKit
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public enum FileOpsError: Error, Equatable, CustomStringConvertible {
    /// The two paths are on different filesystems. Placing never falls back
    /// to a copy: a copy is not atomic, and a media server can see half a file.
    case crossesFilesystems(String, String)
    case system(String, Int32)

    public var description: String {
        switch self {
        case .crossesFilesystems(let a, let b): "\(a) and \(b) are on different filesystems"
        case .system(let op, let code): "\(op) failed: \(String(cString: strerror(code)))"
        }
    }
}

public struct SystemFileOps: FileOps {
    public init() {}

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func contents(of directory: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory).sorted()
    }

    public func read(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// Written beside the target and renamed over it, so a reader never sees
    /// a half-written NFO.
    public func write(_ data: Data, to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try createDirectory(dir)
        let tmp = dir + "/.cylindarr-" + UUID().uuidString
        try data.write(to: URL(fileURLWithPath: tmp))
        try rename(tmp, to: path)
    }

    public func createDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public func rename(_ from: String, to: String) throws {
        let r = from.withCString { f in to.withCString { t in Foundation.rename(f, t) } }
        guard r == 0 else {
            let code = errno
            if code == EXDEV { throw FileOpsError.crossesFilesystems(from, to) }
            throw FileOpsError.system("rename", code)
        }
    }

    /// Adoption's move: a rename where it can be, otherwise copy beside the
    /// target, check the size, rename into place, and only then remove the
    /// source. Placing a download never does this; bringing in an old tree
    /// from another export has to.
    public func relocate(_ from: String, to: String) throws {
        try createDirectory((to as NSString).deletingLastPathComponent)
        do {
            try rename(from, to: to)
            return
        } catch FileOpsError.crossesFilesystems {}
        let partial = to + ".cylindarr-partial"
        try? FileManager.default.removeItem(atPath: partial)
        try FileManager.default.copyItem(atPath: from, toPath: partial)
        let a = (try FileManager.default.attributesOfItem(atPath: from)[.size] as? NSNumber)?.int64Value
        let b = (try FileManager.default.attributesOfItem(atPath: partial)[.size] as? NSNumber)?.int64Value
        guard a != nil, a == b else {
            try? FileManager.default.removeItem(atPath: partial)
            throw FileOpsError.system("copy (size mismatch)", EIO)
        }
        try rename(partial, to: to)
        try FileManager.default.removeItem(atPath: from)
    }

    /// Every file under `root`, relative to it, skipping Synology's `@eaDir`
    /// and dot files.
    public func walk(_ root: String) -> [String] {
        guard let e = FileManager.default.enumerator(atPath: root) else { return [] }
        var out: [String] = []
        while let p = e.nextObject() as? String {
            if p.contains("@eaDir") || (p as NSString).lastPathComponent.hasPrefix(".") {
                if (e.fileAttributes?[.type] as? FileAttributeType) == .typeDirectory { e.skipDescendants() }
                continue
            }
            if (e.fileAttributes?[.type] as? FileAttributeType) == .typeRegular { out.append(p) }
        }
        return out.sorted()
    }

    public func remove(_ path: String) throws {
        guard exists(path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }

    public func freeBytes(at path: String) throws -> Int64 {
        var s = statvfs()
        guard statvfs(path, &s) == 0 else { throw FileOpsError.system("statvfs", errno) }
        return Int64(s.f_bavail) * Int64(s.f_frsize)
    }
}
