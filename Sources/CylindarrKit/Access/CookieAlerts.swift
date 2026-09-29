import Foundation

/// When to tell someone the cookies need replacing. Once when the signed-in
/// check starts failing, not every hour after, and once when a required
/// cookie is a week from its expiry. Nothing when they work again: uploading
/// new ones is what fixes them, so the person already knows.
public struct CookieAlerts: Sendable, Equatable {
    public static let expiryWarning: TimeInterval = 7 * 86_400

    /// The signed-in check failed last time it could be judged.
    public private(set) var failing = false
    /// The expiry already warned about, so a new jar with a new date warns again.
    public private(set) var warnedExpiry: Date?

    public init() {}

    /// Folds in a Verify report and returns what to send. `expiry` is the jar's
    /// earliest required expiry, if there is a jar.
    public mutating func messages(for report: Verifier.Report, expiry: Date?, time: (Date) -> String, day: (Date) -> String) -> [String] {
        var out: [String] = []
        switch report.cookies {
        case .off:
            failing = false
            warnedExpiry = nil
            return []
        case .ok:
            failing = false
        case .failed(let why):
            // With anonymous extraction failing too, YouTube is refusing
            // everything and the queue's pause says so; this is not the
            // cookies' fault, and the state is left as it was.
            guard report.extraction.isOK else { return [] }
            if !failing {
                failing = true
                out.append("The YouTube cookies stopped working at \(time(report.at)) (\(why)). Upload a fresh cookies.txt on Cylindarr's settings page.")
            }
        }
        if !failing, let expiry, expiry > report.at, expiry.timeIntervalSince(report.at) <= Self.expiryWarning, warnedExpiry != expiry {
            warnedExpiry = expiry
            out.append("The YouTube cookies expire on \(day(expiry)). Upload a fresh cookies.txt on Cylindarr's settings page before then.")
        }
        return out
    }
}
