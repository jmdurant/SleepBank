import Foundation

/// Resolves overlapping sleep sources into one non-overlapping timeline.
/// A source with sleep stages takes precedence over a duration-only source;
/// ties use source ID, so query ordering cannot change the result. Other sources
/// fill uncovered intervals. In-bed envelopes never obscure sleep/awake stages.
public enum SleepTimeline {
    public enum Stage: String, Sendable {
        case inBed, awake, asleep, core, deep, rem

        public var isAsleep: Bool { self != .inBed && self != .awake }
        private var specificity: Int {
            switch self {
            case .inBed: return 0
            case .asleep: return 1
            case .core: return 2
            case .rem: return 3
            case .deep: return 4
            case .awake: return 5
            }
        }
        fileprivate var rank: Int { specificity }
    }

    public struct Sample: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let stage: Stage
        public let source: String

        public init(start: Date, end: Date, stage: Stage, source: String) {
            self.start = start; self.end = end; self.stage = stage; self.source = source
        }
        public var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    public static func resolve(_ samples: [Sample], within window: DateInterval? = nil) -> [Sample] {
        let clipped = samples.compactMap { s -> Sample? in
            let start = max(s.start, window?.start ?? s.start)
            let end = min(s.end, window?.end ?? s.end)
            guard end > start else { return nil }
            return Sample(start: start, end: end, stage: s.stage, source: s.source)
        }
        let stagedSources = Set(clipped.filter { [.core, .deep, .rem].contains($0.stage) }.map(\.source))
        struct Event { let date: Date; let index: Int; let starts: Bool }
        let events = clipped.enumerated().flatMap { i, s in
            [Event(date: s.start, index: i, starts: true), Event(date: s.end, index: i, starts: false)]
        }.sorted { $0.date < $1.date }
        var active: [Int: Sample] = [:]
        var result: [Sample] = []
        var i = 0
        while i < events.count {
            let date = events[i].date
            while i < events.count, events[i].date == date {
                let e = events[i]
                if e.starts { active[e.index] = clipped[e.index] }
                else { active.removeValue(forKey: e.index) }
                i += 1
            }
            guard i < events.count, let chosen = active.values.sorted(by: { a, b in
                if (a.stage == .inBed) != (b.stage == .inBed) { return b.stage == .inBed }
                if stagedSources.contains(a.source) != stagedSources.contains(b.source) {
                    return stagedSources.contains(a.source)
                }
                if a.source != b.source { return a.source < b.source }
                return a.stage.rank > b.stage.rank
            }).first else { continue }
            let end = events[i].date
            if let last = result.last, last.end == date,
               last.stage == chosen.stage, last.source == chosen.source {
                result[result.count - 1] = Sample(start: last.start, end: end, stage: last.stage, source: last.source)
            } else {
                result.append(Sample(start: date, end: end, stage: chosen.stage, source: chosen.source))
            }
        }
        return result
    }
}
