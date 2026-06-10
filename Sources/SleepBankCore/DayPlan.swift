import Foundation

/// Turns the day's `AlertnessRhythm` into an actionable agenda — the "response
/// layer" to a readiness score. Readiness apps tell you the day is compromised;
/// this says *what to do about it and when*: get morning light, nap before the
/// afternoon dip, wind down in time. Pure facts/timings here; the view supplies the
/// wording.
public struct DayPlan: Sendable, Equatable {

    public enum Kind: String, Sendable { case morningLight, morningMovement, nap, dip, windDown }

    public struct Item: Sendable, Equatable {
        public let kind: Kind
        /// When to act. `nil` means "now / as soon as you can."
        public let time: Date?
        /// Already satisfied today (shown as a ✓ rather than a to-do).
        public let done: Bool
        public init(kind: Kind, time: Date?, done: Bool) {
            self.kind = kind
            self.time = time
            self.done = done
        }
    }

    /// Predicted alertness at wake (0…1) — how the day starts.
    public let startingLevel: Double
    public let isShortNight: Bool
    /// The day's predicted afternoon low, if it's still ahead.
    public let dipTime: Date?
    public let dipLevel: Double
    /// Suggested nap start (≈40 min before the dip), if a nap would help and it's
    /// still ahead. `nil` if the dip has passed or the day looks fine.
    public let suggestedNap: Date?
    public let items: [Item]

    public static func build(rhythm: AlertnessRhythm, now: Date,
                             calendar: Calendar = .current) -> DayPlan {
        let wake = rhythm.wakeTime
        let startingLevel = rhythm.level(at: wake)
        let base = calendar.startOfDay(for: now)
        func at(_ hour: Double) -> Date { base.addingTimeInterval(hour * 3600) }

        // Afternoon dip = lowest predicted point between 11:00 and 17:30.
        var dipTime = at(15)
        var dipLevel = 1.0
        var t = at(11)
        let dipEnd = at(17.5)
        while t <= dipEnd {
            let level = rhythm.level(at: t)
            if level < dipLevel { dipLevel = level; dipTime = t }
            t = t.addingTimeInterval(15 * 60)
        }
        let dipAhead = dipTime > now

        // Nap ~40 min before the dip, so the nap + waking lands you into it refreshed.
        // Only when the dip is ahead and low enough to be worth it.
        let napWorthwhile = dipAhead && dipLevel < 0.62
        let suggestedNap = napWorthwhile ? max(dipTime.addingTimeInterval(-40 * 60), now) : nil

        let morningEnd = wake.addingTimeInterval(4 * 3600)
        let lightDone = rhythm.morningLightDose >= 0.5
        let moveDone = rhythm.morningActivityDose >= 0.5
        let inMorning = now < morningEnd
        let windDown = wake.addingTimeInterval(16 * 3600)

        var items: [Item] = []
        if lightDone || inMorning {
            items.append(Item(kind: .morningLight, time: lightDone ? nil : now, done: lightDone))
        }
        if moveDone || inMorning {
            items.append(Item(kind: .morningMovement, time: moveDone ? nil : now, done: moveDone))
        }
        if let nap = suggestedNap {
            items.append(Item(kind: .nap, time: nap, done: false))
        }
        if dipAhead {
            items.append(Item(kind: .dip, time: dipTime, done: false))
        }
        items.append(Item(kind: .windDown, time: windDown, done: false))

        items.sort { ($0.time ?? now) < ($1.time ?? now) }

        return DayPlan(startingLevel: startingLevel, isShortNight: rhythm.isShortNight,
                       dipTime: dipAhead ? dipTime : nil, dipLevel: dipLevel,
                       suggestedNap: suggestedNap, items: items)
    }
}
