import Foundation

/// Resolve: what a grab's URL from a site other than YouTube is, before
/// anything is downloaded. One `yt-dlp -J` call says which extractor takes
/// it, the site's id, the title and whether it is one video with a picture.
/// A YouTube URL never comes here: full extraction is what YouTube's bot
/// check watches, so YouTube's is spent only on downloads, and its id is in
/// the URL already.
public enum Resolve {
    public enum Decision: Equatable, Sendable {
        case resolved(key: String, title: String, uploaded: Date?)
        case failed(FailCause, detail: String)
        case deferred(DeferCause, detail: String)
    }

    /// Flat, so a channel or album is recognised from its first entry
    /// instead of every video in it being extracted.
    public static func arguments(url: String, proxy: String?) -> [String] {
        var a = ["-J", "--no-playlist", "--flat-playlist", "--playlist-end", "1", "--no-warnings"]
        if let proxy { a += ["--proxy", proxy] }
        a.append(url)
        return a
    }

    public static func decide(_ run: ProcessResult) -> Decision {
        guard run.exitCode == 0 else {
            let tail = FailureClassifier.tail(of: run.stderr, lines: 2)
            switch FailureClassifier.diagnose(stderr: run.stderr) {
            case .deferred(let cause): return .deferred(cause, detail: tail)
            case .failed(let cause), .needsCookies(let cause): return .failed(cause, detail: tail)
            }
        }
        guard let info = try? VideoInfo.decode(run.stdout) else {
            return .failed(.unrecognised, detail: "yt-dlp's description of the URL could not be read")
        }
        if info.type == "playlist" {
            return .failed(.notOneVideo, detail: info.title)
        }
        if info.vcodec == "none" {
            return .failed(.notVideo, detail: info.title)
        }
        let key = VideoKey.make(extractor: info.extractorKey ?? "generic", id: info.id)
        return .resolved(key: key, title: info.title, uploaded: info.uploaded)
    }
}
