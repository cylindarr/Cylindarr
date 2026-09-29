import Foundation

/// How downloads are encoded. Every video is encoded to HEVC once, after the
/// download and before it is placed, and that one pass is also where the
/// SponsorBlock segments are cut.
///
/// yt-dlp's own cut (`--sponsorblock-remove`) copies the streams through
/// ffmpeg's concat demuxer, which can start a piece only on a keyframe. The
/// frames and audio between that keyframe and the end of the segment are kept
/// and squeezed into a millisecond before the cut, up to a whole GOP of them
/// (5.6 seconds on YouTube), and players that play the squeezed audio drift
/// out of sync from the first cut on (found 2026-09-28, in 66 of the 132
/// videos then in the library). Cutting while encoding makes every cut exact.
public struct EncodeSettings: Sendable, Equatable {
    public enum Encoder: Sendable, Equatable {
        /// Intel Quick Sync, through the VA-API render node given. Low power
        /// is the fixed-function encoder that Ice Lake and later have; older
        /// Intel graphics encode HEVC only in the default mode.
        case quickSync(device: String, lowPower: Bool = true)
        /// VA-API on any GPU with a driver for it (AMD through Mesa, or Intel).
        case vaapi(device: String)
        /// NVIDIA NVENC, with the card passed in by the NVIDIA container runtime.
        case nvenc
        /// libx265 on the CPU, for a machine with no usable GPU.
        case software
        /// No encode: the download is placed as YouTube served it, and
        /// SponsorBlock segments are marked as chapters rather than cut.
        case none
    }

    public var encoder: Encoder
    /// The constant QP for the GPU encoders, `-crf` for libx265. Lower is
    /// better and larger.
    ///
    /// 24 was measured on two minutes of a 1080p video from YouTube's AV1
    /// (1.03 Mbps): Quick Sync's low-power encoder at QP 24 made 1.11 Mbps at
    /// 45.5 dB PSNR against the source; QP 22 made 1.49 Mbps at 47.0 dB, as
    /// libx265's CRF 24 did at 1.37 Mbps; QP 27 made 0.77 Mbps at 43.5 dB.
    /// About the source's own bitrate, and half YouTube's H.264.
    public var quality: Int

    public init(encoder: Encoder = .software, quality: Int = 24) {
        self.encoder = encoder
        self.quality = quality
    }

    /// Whether downloads go through ffmpeg at all.
    public var encodes: Bool { encoder != .none }

    public var name: String {
        switch encoder {
        case .quickSync: "Quick Sync"
        case .vaapi: "VA-API"
        case .nvenc: "NVENC"
        case .software: "libx265"
        case .none: "no encoder"
        }
    }

    /// The same settings with Quick Sync's default mode, for a GPU whose
    /// low-power encoder refused. Nil when there is nothing to fall back to.
    public var withoutLowPower: EncodeSettings? {
        guard case .quickSync(let device, true) = encoder else { return nil }
        return EncodeSettings(encoder: .quickSync(device: device, lowPower: false), quality: quality)
    }
}

public enum Transcode {
    /// The ffmpeg command line for one video. `cuts` empty means nothing is
    /// cut. `chapters` is an ffmetadata file replacing the source's chapters,
    /// which a cut leaves pointing at the wrong moments.
    ///
    /// A cut is one filter chain per stream: `select` drops the frames in the
    /// removed ranges and `setpts` moves each one left by the time removed
    /// before it, the same expression for video and audio, so the two cannot
    /// drift apart. (Trimming each kept piece and joining them with `concat`
    /// is the textbook way, and it held every frame bound for a later piece in
    /// memory: 26 GB and the OOM killer, 2026-09-28.)
    public static func arguments(input: String, output: String, cuts: CutList, chapters: String?,
                                 hasAudio: Bool, audioIsAAC: Bool, settings: EncodeSettings) -> [String] {
        var a = ["-hide_banner", "-nostdin", "-nostats", "-y", "-v", "error"]
        // Frames are decoded and cut on the CPU and uploaded to the GPU for
        // the encoder: YouTube's VP9 and AV1 decode quickly in software, and
        // the filters need frames they can read.
        let upload: String
        switch settings.encoder {
        case .quickSync(let device, _):
            a += ["-init_hw_device", "vaapi=va:\(device)", "-init_hw_device", "qsv=qs@va", "-filter_hw_device", "qs"]
            upload = "format=nv12,hwupload=extra_hw_frames=64"
        case .vaapi(let device):
            a += ["-init_hw_device", "vaapi=va:\(device)", "-filter_hw_device", "va"]
            upload = "format=nv12,hwupload"
        case .nvenc, .software, .none:
            // NVENC takes frames from system memory itself.
            upload = "format=yuv420p"
        }
        a += ["-i", input]
        if let chapters { a += ["-i", chapters] }
        a += ["-map", "0:v:0", "-map", "0:a:0?"]

        if cuts.isEmpty {
            a += ["-vf", upload]
        } else {
            let (select, shift) = expressions(cuts)
            a += ["-vf", "select='\(select)',setpts='PTS-(\(shift))/TB',\(upload)"]
            // Audio is dropped a whole frame (about 21 ms) at a time; aresample
            // closes the few samples of gap or overlap that leaves at a cut.
            if hasAudio { a += ["-af", "aselect='\(select)',asetpts='PTS-(\(shift))/TB',aresample=async=1"] }
            // Timestamps as moved, not snapped back onto a frame grid.
            a += ["-fps_mode", "vfr"]
        }

        let q = String(settings.quality)
        switch settings.encoder {
        case .quickSync(_, let lowPower):
            // The low-power (VDENC) encoder: fixed-function, four times the
            // speed of the default mode on an 11th-generation Intel laptop chip's
            // UHD graphics (10.7x real time against 2.8x) and as good at the same
            // bitrate. It has no ICQ, so constant QP.
            a += ["-c:v", "hevc_qsv"] + (lowPower ? ["-low_power", "1"] : []) + ["-preset", "slow", "-q:v", q]
        case .vaapi:
            a += ["-c:v", "hevc_vaapi", "-rc_mode", "CQP", "-qp", q]
        case .nvenc:
            a += ["-c:v", "hevc_nvenc", "-preset", "p5", "-rc", "constqp", "-qp", q]
        case .software, .none:
            a += ["-c:v", "libx265", "-preset", "medium", "-crf", q, "-x265-params", "log-level=error"]
        }
        // `hvc1`, not ffmpeg's default `hev1`: Apple's players refuse the other.
        a += ["-tag:v", "hvc1"]
        // Cut audio has to be encoded; uncut AAC is copied as it came.
        a += cuts.isEmpty && audioIsAAC ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "160k"]
        a += ["-map_metadata", "0", "-map_chapters", chapters != nil ? "1" : cuts.isEmpty ? "0" : "-1"]
        a += ["-movflags", "+faststart", output]
        return a
    }

    /// The frames to keep, and how far to move each one, as ffmpeg
    /// expressions of its time `t` (`T` in setpts). A frame at or after a
    /// range's end moves left by that range's length.
    static func expressions(_ cuts: CutList) -> (select: String, shift: String) {
        let inside = cuts.removed.map { "gte(t,\(seconds($0.start)))*lt(t,\(seconds($0.end)))" }
        let shift = cuts.removed.map { "gte(T,\(seconds($0.end)))*\(seconds($0.end - $0.start))" }
        return ("not(\(inside.joined(separator: "+")))", shift.joined(separator: "+"))
    }

    /// An ffmetadata file of the video's chapters, moved by the cuts. A
    /// chapter the cuts leave shorter than a second goes.
    public static func chapters(_ chapters: [VideoInfo.Chapter], cuts: CutList) -> String? {
        let moved = chapters.compactMap { c -> (Double, Double, String)? in
            let start = cuts.map(c.startTime), end = cuts.map(c.endTime)
            return end - start >= 1 ? (start, end, c.title) : nil
        }
        guard !moved.isEmpty else { return nil }
        var lines = [";FFMETADATA1"]
        for (start, end, title) in moved {
            lines += ["[CHAPTER]", "TIMEBASE=1/1000", "START=\(Int((start * 1000).rounded()))",
                      "END=\(Int((end * 1000).rounded()))", "title=\(escape(title))"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// ffmetadata's special characters are escaped with a backslash.
    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "=;#\\\n".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    static func seconds(_ t: Double) -> String { String(format: "%.3f", t) }
}
