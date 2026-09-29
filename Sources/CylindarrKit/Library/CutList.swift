import Foundation

/// The SponsorBlock segments removed from a video, as time arithmetic: where
/// a moment in the original lands in the cut video. The encoder, the chapters and the subtitle sidecars all
/// use the one list, so they cannot disagree about a cut.
public struct CutList: Sendable, Equatable {
    /// Merged, sorted, non-empty ranges in the original video's time.
    public let removed: [Range]

    public struct Range: Sendable, Equatable {
        public var start: Double
        public var end: Double
        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }
    }

    public init(_ ranges: [(start: Double, end: Double)]) {
        var out: [Range] = []
        for r in ranges.filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            if let last = out.last, r.start <= last.end {
                out[out.count - 1].end = max(last.end, r.end)
            } else {
                out.append(Range(start: max(r.start, 0), end: r.end))
            }
        }
        removed = out
    }

    /// The segments of the chosen categories that have both ends.
    public init(segments: [VideoInfo.SponsorBlockSegment], categories: [String]) {
        self.init(segments.filter { categories.contains($0.category ?? "") }
            .compactMap { s in s.startTime.flatMap { a in s.endTime.map { (start: a, end: $0) } } })
    }

    public var isEmpty: Bool { removed.isEmpty }

    /// How much of a video `duration` seconds long the cuts remove.
    public func removedLength(of duration: Double) -> Double {
        removed.reduce(0) { $0 + max(0, min($1.end, duration) - $1.start) }
    }

    /// A moment in the original, in the cut video. Inside a removed range it
    /// lands where that range was.
    public func map(_ t: Double) -> Double {
        var shift = 0.0
        for r in removed {
            if t >= r.end { shift += r.end - r.start } else if t > r.start { return r.start - shift }
        }
        return t - shift
    }
}
