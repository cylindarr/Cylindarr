import Foundation

/// Cuts an SRT file to match a video SponsorBlock segments were removed from.
///
/// yt-dlp's own cutting of subtitle sidecars, through ffmpeg's concat
/// demuxer, fails ("Error opening input files: Result too large") with
/// ffmpeg 6.1 and 8.1 alike, for SRT and WebVTT alike (tested 2026-09-27).
/// Pinchflat's tree carries the leftover `.en.temp.srt.concat` from the same
/// failure. Cylindarr cuts the video itself (see Transcode), and the
/// subtitles, fetched afterwards from the saved info.json, are moved here by
/// the same CutList.
public enum SubtitleCutter {
    public struct Cue: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var text: String
    }

    public static func parse(_ srt: String) -> [Cue] {
        let normalized = srt.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        var cues: [Cue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = seconds(parts[0]), let end = seconds(parts[1]) else { continue }
            let text = lines[(timing + 1)...].joined(separator: "\n").trimmingCharacters(in: .newlines)
            cues.append(Cue(start: start, end: end, text: text))
        }
        return cues
    }

    /// A cue inside a removed range goes; a cue across one's edge is clipped
    /// to what remains; every time after a cut moves back by the length of
    /// the cuts before it.
    public static func cut(_ cues: [Cue], removing cuts: CutList) -> [Cue] {
        cues.compactMap { cue in
            let start = cuts.map(cue.start), end = cuts.map(cue.end)
            return end - start >= 0.05 ? Cue(start: start, end: end, text: cue.text) : nil
        }
    }

    public static func render(_ cues: [Cue]) -> String {
        cues.enumerated().map { i, c in "\(i + 1)\n\(timestamp(c.start)) --> \(timestamp(c.end))\n\(c.text)\n" }
            .joined(separator: "\n")
    }

    static func seconds(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = s.split(separator: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]),
              let sec = Double(parts[2].split(separator: " ")[0]) else { return nil }
        return h * 3600 + m * 60 + sec
    }

    static func timestamp(_ t: Double) -> String {
        let ms = Int((max(t, 0) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    /// YouTube names some tracks `en-j3PyPqV-e1s` (a language and a track
    /// id). The sidecar is named for the language, with a region kept when it
    /// is one (`en-GB`).
    public static func languageTag(_ code: String) -> String {
        let parts = code.split(separator: "-")
        guard parts.count > 1 else { return code }
        let second = parts[1]
        if second.count == 2, second.allSatisfy(\.isLetter) { return "\(parts[0])-\(second.uppercased())" }
        return String(parts[0])
    }
}
