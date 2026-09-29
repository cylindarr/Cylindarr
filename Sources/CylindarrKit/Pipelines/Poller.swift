import Foundation

/// Poll: notice new videos. The feed first, because it is one plain request
/// and never meets the bot check; yt-dlp's flat listing whenever the feed
/// does not answer, because on 2026-09-27 the feeds answered real channels
/// and playlists with a 404 page most of the time. The listing passes from
/// addresses where full extraction meets the bot check. Either way each new video is `consider`ed and recorded, and the
/// poll writes one summary Entry.
public struct Poller: Sendable {
    public let feeds: FeedClient
    public let ytdlp: YtDlp
    public let store: VideoStore
    public let journal: Journal
    public let clock: Clock
    public static let feedFailuresBeforeListing = 1
    public static let listingDepth = 20

    public init(feeds: FeedClient, ytdlp: YtDlp, store: VideoStore, journal: Journal, clock: Clock) {
        self.feeds = feeds
        self.ytdlp = ytdlp
        self.store = store
        self.journal = journal
        self.clock = clock
    }

    public struct Result: Equatable, Sendable {
        public var source: Source
        public var new: [String] = []
        public var wanted: [String] = []
        public var feedFailed = false
        public var feedError: String?
        public enum Source: String, Sendable { case feed, listing, none }
    }

    /// `feedFailures` is how many polls in a row the feed has failed before
    /// this one. The caller keeps it on the subscription and resets it on
    /// success.
    public func poll(_ sub: Subscription, feedFailures: Int) async -> Result {
        var result = Result(source: .none)
        var candidates: [Candidate] = []

        do {
            let data = try await feeds.get(sub.feedURL)
            let feed = try FeedParser.parse(data)
            candidates = feed.entries.map(Candidate.init)
            result.source = .feed
        } catch let e as HTTPFailure {
            result.feedFailed = true
            switch e {
            case .status(let code): result.feedError = "HTTP \(code)"
            case .transport(let why): result.feedError = why
            }
        } catch {
            result.feedFailed = true
            result.feedError = error is FeedError ? "not a feed" : "\(error)"
        }

        if result.feedFailed, feedFailures + 1 >= Poller.feedFailuresBeforeListing {
            let args = ["-J", "--flat-playlist", "--playlist-end", String(Poller.listingDepth), "--no-warnings",
                        "--extractor-args", "youtubetab:approximate_date", sub.listingURL.absoluteString]
            let run = await ytdlp.run(args)
            if run.exitCode == 0, let listing = try? Listing.decode(run.stdout) {
                candidates = listing.entries.filter { !$0.isPlaceholder }.map {
                    Candidate(id: $0.id, title: $0.title ?? $0.id, duration: $0.duration.map { Int($0) },
                              liveStatus: $0.liveStatus,
                              approximatelyUploaded: $0.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) })
                }
                result.source = .listing
            }
        }

        guard result.source != .none else {
            journal.record(Entry(verb: .poll, noun: .subscription, subject: sub.name, outcome: .deferred,
                                 detail: "feed did not answer (\(result.feedError ?? "?"), \(feedFailures + 1) in a row)"))
            return result
        }

        await consider(candidates, of: sub, into: &result)
        let how = result.source == .listing ? " (from the listing; the feed did not answer)" : ""
        let tail = result.new.isEmpty ? "nothing new" : "\(result.new.count) new, \(result.wanted.count) wanted: \(result.wanted.joined(separator: " "))"
        journal.record(Entry(verb: .poll, noun: .subscription, subject: sub.name, outcome: .ok, detail: tail + how))
        return result
    }

    /// Enumerate: the whole channel or playlist, not just its newest. A poll
    /// sees 15 videos from the feed or 20 from the listing, which is enough
    /// to notice new uploads and not enough to fill a back catalogue. This is
    /// one flat listing, paged by yt-dlp, with no extraction per video, so it
    /// does not meet the bot check. Every video not seen before is
    /// considered, and one skipped earlier for its date (before the cutoff,
    /// or past the retention rule) is considered again under today's rules.
    public func enumerate(_ sub: Subscription) async -> Result {
        var result = Result(source: .none)
        let args = ["-J", "--flat-playlist", "--no-warnings", "--extractor-args", "youtubetab:approximate_date",
                    sub.listingURL.absoluteString]
        let run = await ytdlp.run(args)
        guard run.exitCode == 0, let listing = try? Listing.decode(run.stdout) else {
            journal.record(Entry(verb: .enumerate, noun: .subscription, subject: sub.name, outcome: .failed,
                                 detail: FailureClassifier.tail(of: run.stderr, lines: 1)))
            return result
        }
        result.source = .listing
        let candidates = listing.entries.filter { !$0.isPlaceholder }.map {
            Candidate(id: $0.id, title: $0.title ?? $0.id, duration: $0.duration.map { Int($0) },
                      liveStatus: $0.liveStatus,
                      approximatelyUploaded: $0.timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) })
        }
        var revived: [String] = []
        for c in candidates {
            guard var r = try? await store.video(c.id), r.subscriptionID == sub.id,
                  r.state == .skipped(.beforeCutoff) || r.state == .skipped(.pastRetention) else { continue }
            let again = Candidate(id: r.id, title: r.title, uploaded: r.uploaded,
                                  approximatelyUploaded: r.approximatelyUploaded ?? c.approximatelyUploaded)
            guard Consider.decide(again, rules: sub.rules, now: clock.now) == .want else { continue }
            r.state = .wanted
            r.attempts = 0
            try? await store.save(r)
            revived.append(r.id)
        }
        await consider(candidates, of: sub, into: &result)
        result.wanted += revived
        journal.record(Entry(verb: .enumerate, noun: .subscription, subject: sub.name, outcome: .ok,
                             detail: "\(candidates.count) listed, \(result.new.count) new, \(result.wanted.count) wanted"))
        return result
    }

    /// Records every candidate not seen before, with what the rules decide.
    func consider(_ candidates: [Candidate], of sub: Subscription, into result: inout Result) async {
        for c in candidates {
            do {
                if try await store.video(c.id) != nil { continue }
                result.new.append(c.id)
                let decision = sub.isGrabList ? .want : Consider.decide(c, rules: sub.rules, now: clock.now)
                let state: VideoState
                switch decision {
                case .want:
                    state = .wanted
                    result.wanted.append(c.id)
                case .skip(let reason): state = .skipped(reason)
                case .wait(let cause): state = .deferred(cause, until: clock.now.addingTimeInterval(cause.backoff(afterAttempt: 1)))
                }
                try await store.save(VideoRecord(id: c.id, subscriptionID: sub.id, title: c.title, uploaded: c.uploaded,
                                                 state: state, firstSeen: clock.now,
                                                 approximatelyUploaded: c.approximatelyUploaded))
                journal.record(Entry(verb: .consider, noun: .video, subject: c.id, outcome: outcome(state),
                                     detail: detail(state, title: c.title)))
            } catch {
                journal.record(Entry(verb: .consider, noun: .video, subject: c.id, outcome: .failed,
                                     detail: "could not record: \(error)"))
            }
        }
    }

    func outcome(_ s: VideoState) -> Outcome {
        switch s {
        case .wanted: .wanted
        case .skipped: .skipped
        case .deferred: .deferred
        default: .ok
        }
    }

    func detail(_ s: VideoState, title: String) -> String {
        switch s {
        case .skipped(let r): "\(r.sentence): \(title)"
        case .deferred(let c, _): "\(c.rawValue): \(title)"
        default: title
        }
    }
}
