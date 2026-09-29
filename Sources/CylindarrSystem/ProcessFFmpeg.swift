import Foundation
import CylindarrKit

/// ffmpeg as a child process, run the way yt-dlp is.
public struct ProcessFFmpeg: FFmpeg {
    public let executable: String
    public let timeout: TimeInterval

    public init(executable: String = ProcessFFmpeg.defaultExecutable, timeout: TimeInterval = 6 * 3600) {
        self.executable = executable
        self.timeout = timeout
    }

    /// `CYLINDARR_FFMPEG`, else the distribution's, else Homebrew's.
    public static var defaultExecutable: String {
        if let path = ProcessInfo.processInfo.environment["CYLINDARR_FFMPEG"], !path.isEmpty { return path }
        return ["/usr/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/ffmpeg"
    }

    public func run(_ arguments: [String]) async -> ProcessResult {
        await ProcessYtDlp.run(executable, arguments, timeout: timeout)
    }

    public func duration(of path: String) async -> Double? {
        let probe = (executable as NSString).deletingLastPathComponent + "/ffprobe"
        let r = await ProcessYtDlp.run(probe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                                       timeout: 120)
        guard r.exitCode == 0 else { return nil }
        return Double(String(decoding: r.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The encoder for the settings page's choice. `auto` is Quick Sync when
    /// an Intel GPU's render node is in the container and the CPU otherwise;
    /// AMD and NVIDIA are used only when chosen. A node is found by its
    /// vendor rather than assumed, because which `renderD` number a GPU gets
    /// depends on the order the drivers load: with an Intel and an NVIDIA
    /// card in one machine, the NVIDIA one can be `renderD128`.
    public static func encoder(choice: String = "auto", sysfs: String = "/sys/class/drm",
                               devices: String = "/dev/dri") -> EncodeSettings.Encoder {
        let nodes = renderNodes(sysfs: sysfs, devices: devices)
        let intel = nodes.first { $0.vendor == intelVendor }?.path
        switch choice {
        case "none": return .none
        case "software": return .software
        case "nvenc": return .nvenc
        case "quicksync": return .quickSync(device: intel ?? nodes.first?.path ?? devices + "/renderD128")
        case "vaapi":
            let amd = nodes.first { $0.vendor == amdVendor }?.path
            return .vaapi(device: amd ?? intel ?? nodes.first?.path ?? devices + "/renderD128")
        default: return intel.map { .quickSync(device: $0) } ?? .software
        }
    }

    static let intelVendor = "0x8086"
    static let amdVendor = "0x1002"

    /// Every readable render node in the container, with its PCI vendor id.
    static func renderNodes(sysfs: String, devices: String) -> [(path: String, vendor: String?)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: sysfs)) ?? []
        return names.sorted().filter { $0.hasPrefix("renderD") }.compactMap { name in
            let node = "\(devices)/\(name)"
            guard FileManager.default.isReadableFile(atPath: node) else { return nil }
            let vendor = (try? String(contentsOfFile: "\(sysfs)/\(name)/device/vendor", encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (node, vendor)
        }
    }
}
