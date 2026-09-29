import Foundation
@preconcurrency import Dispatch
import CylindarrKit

/// yt-dlp as a child process. Both pipes are drained while it runs, because
/// a `-J` of a long channel is megabytes and a full pipe blocks the child.
public struct ProcessYtDlp: YtDlp {
    public let executable: String
    public let environment: [String: String]
    public let timeout: TimeInterval

    public init(executable: String, environment: [String: String] = [:], timeout: TimeInterval = 6 * 3600) {
        self.executable = executable
        self.environment = environment
        self.timeout = timeout
    }

    public func run(_ arguments: [String]) async -> ProcessResult {
        await Self.run(executable, arguments, environment: environment, timeout: timeout)
    }

    public static func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:],
                           timeout: TimeInterval) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            for (k, v) in environment { env[k] = v }
            process.environment = env
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice

            let collector = Collector()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                collector.setOut(out.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                collector.setErr(err.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: ProcessResult(exitCode: 127, stdout: Data(), stderr: "ERROR: could not start \(executable): \(error)"))
                return
            }
            let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            DispatchQueue.global().async {
                process.waitUntilExit()
                deadline.cancel()
                group.wait()
                let (o, e) = collector.values
                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus, stdout: o, stderr: String(decoding: e, as: UTF8.self)))
            }
        }
    }

    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data(), err = Data()
        func setOut(_ d: Data) { lock.lock(); out = d; lock.unlock() }
        func setErr(_ d: Data) { lock.lock(); err = d; lock.unlock() }
        var values: (Data, Data) { lock.lock(); defer { lock.unlock() }; return (out, err) }
    }
}
