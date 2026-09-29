import Foundation

/// Whether fetching may run. One bot check is one video's bad luck; three in
/// a row is the address, and retrying into it is what keeps an address
/// flagged, so the whole queue stops until Verify passes or the pause ends.
/// A full disk and a rate limit stop it at once.
public struct QueueGate: Sendable, Equatable {
    public private(set) var consecutiveBotChecks = 0
    public private(set) var pausedUntil: Date?
    public private(set) var reason: DeferCause?
    public static let botChecksBeforePause = 3

    public init() {}

    public func isOpen(at now: Date) -> Bool {
        guard let until = pausedUntil else { return true }
        return now >= until
    }

    public mutating func record(_ outcome: Fetcher.Outcome, at now: Date) {
        switch outcome {
        case .deferred(.botCheck):
            consecutiveBotChecks += 1
            if consecutiveBotChecks >= QueueGate.botChecksBeforePause {
                pause(.botCheck, for: DeferCause.botCheck.backoff(afterAttempt: consecutiveBotChecks - 2), at: now)
            }
        case .deferred(let cause) where cause.pausesQueue:
            pause(cause, for: cause.backoff(afterAttempt: 1), at: now)
        case .placed:
            consecutiveBotChecks = 0
            resume()
        default:
            break
        }
    }

    public mutating func pause(_ cause: DeferCause, for interval: TimeInterval, at now: Date) {
        pausedUntil = now.addingTimeInterval(interval)
        reason = cause
    }

    /// Verify passed, or someone pressed resume.
    public mutating func resume() {
        pausedUntil = nil
        reason = nil
    }
}
