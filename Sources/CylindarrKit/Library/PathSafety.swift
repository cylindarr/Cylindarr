import Foundation

/// Titles become path components. The rules: `/` and `\` become `-`, `:`
/// becomes ` -`, the characters Windows and SMB refuse are removed, runs of
/// whitespace fold, and leading and trailing dots and spaces go. Everything
/// else stays, non-Latin text included. yt-dlp's default of substituting
/// full-width look-alikes (`：`, `？`), which is what Pinchflat's files carry,
/// is undone rather than copied.
public enum PathSafety {
    static let lookalikes: [Character: String] = [
        "：": ":", "？": "?", "／": "/", "＼": "\\", "＊": "*", "＂": "\"", "＜": "<", "＞": ">", "｜": "|",
        "⧸": "/", "⧹": "\\",
    ]

    public static func clean(_ raw: String) -> String {
        var s = ""
        for ch in raw {
            if let plain = lookalikes[ch] { s += plain } else { s.append(ch) }
        }
        s = s.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: "\\", with: "-")
        s = s.replacingOccurrences(of: #"\s*:\s*"#, with: " - ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[?*"<>|]"#, with: "", options: .regularExpression)
        // Whitespace first, so a tab or newline between words becomes a space
        // before the remaining control characters are dropped.
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        s = s.replacingOccurrences(of: #"( - )+"#, with: " - ", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        return s.isEmpty ? "Untitled" : s
    }

    /// Cuts `s` so it fits in `bytes` of UTF-8, at a word boundary where one is
    /// near, never inside a character.
    public static func truncate(_ s: String, toBytes bytes: Int) -> String {
        guard s.utf8.count > bytes else { return s }
        var out = ""
        for ch in s {
            if out.utf8.count + String(ch).utf8.count > bytes { break }
            out.append(ch)
        }
        if let space = out.lastIndex(of: " "), out.distance(from: out.startIndex, to: space) > out.count * 2 / 3 {
            out = String(out[..<space])
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
    }
}
