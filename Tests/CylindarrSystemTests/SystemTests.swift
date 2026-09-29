import Foundation
import Testing
@testable import CylindarrSystem
import CylindarrKit

@Suite struct SystemTests {
    func tempDir() throws -> String {
        let d = NSTemporaryDirectory() + "cylindarr-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    @Test func renamePreservesTheInode() throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: d) }
        let fs = SystemFileOps()
        try fs.write(Data("x".utf8), to: d + "/a.mp4")
        let before = try FileManager.default.attributesOfItem(atPath: d + "/a.mp4")[.systemFileNumber] as? Int
        try fs.createDirectory(d + "/Shows/X/Season 2026")
        try fs.rename(d + "/a.mp4", to: d + "/Shows/X/Season 2026/a.mp4")
        let after = try FileManager.default.attributesOfItem(atPath: d + "/Shows/X/Season 2026/a.mp4")[.systemFileNumber] as? Int
        #expect(before == after)
        #expect(try fs.freeBytes(at: d) > 0)
        #expect(try fs.contents(of: d) == ["Shows"])
    }

    /// Two GPUs, the NVIDIA one first: auto finds the Intel node by vendor.
    @Test func theEncoderIsChosenByVendor() throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: d) }
        for (node, vendor) in [("renderD128", "0x10de"), ("renderD129", "0x8086"), ("renderD130", "0x1002")] {
            try FileManager.default.createDirectory(atPath: "\(d)/sys/\(node)/device", withIntermediateDirectories: true)
            try Data((vendor + "\n").utf8).write(to: URL(fileURLWithPath: "\(d)/sys/\(node)/device/vendor"))
            try FileManager.default.createDirectory(atPath: "\(d)/dev", withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: "\(d)/dev/\(node)", contents: Data())
        }
        func pick(_ choice: String) -> EncodeSettings.Encoder {
            ProcessFFmpeg.encoder(choice: choice, sysfs: d + "/sys", devices: d + "/dev")
        }
        #expect(pick("auto") == .quickSync(device: d + "/dev/renderD129"))
        #expect(pick("vaapi") == .vaapi(device: d + "/dev/renderD130"))
        #expect(pick("nvenc") == .nvenc)
        #expect(pick("none") == EncodeSettings.Encoder.none)
        #expect(ProcessFFmpeg.encoder(choice: "auto", sysfs: d + "/nothing", devices: d + "/dev") == .software)
    }

    @Test func aProcessIsRunAndBothStreamsAreRead() async {
        let r = await ProcessYtDlp.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], timeout: 10)
        #expect(r.exitCode == 3)
        #expect(String(decoding: r.stdout, as: UTF8.self) == "out\n")
        #expect(r.stderr == "err\n")
    }

    /// A large output must not deadlock on a full pipe.
    @Test func largeOutputDoesNotBlock() async {
        let r = await ProcessYtDlp.run("/bin/sh", ["-c", "head -c 3000000 /dev/zero"], timeout: 30)
        #expect(r.exitCode == 0)
        #expect(r.stdout.count == 3_000_000)
    }

    @Test func aMissingExecutableIsAResultNotACrash() async {
        let r = await ProcessYtDlp.run("/nonexistent/yt-dlp", [], timeout: 5)
        #expect(r.exitCode == 127)
    }
}
