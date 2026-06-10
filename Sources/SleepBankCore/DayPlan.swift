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
    /// Suggested nap start — the nearest *calendar-free* slot near ≈40 min before the
    /// dip, if a nap would help and it's still ahead. `nil` if the dip has passed, the
    /// day looks fine, or there's no free moment (see `napBlockedByCalendar`).
    public let suggestedNap: Date?
    /// A nap would help, but every slot near the dip is booked on the calendar.
    public let napBlockedByCalendar: Bool
    public let items: [Item]

    /// `busy` = the user's calendar events (the app reads EventKit; the core just
    /// avoids them) — so the nap is suggested in a free moment, not on top of a meeting.
    public static func build(rhythm: AlertnessRhythm, now: Date,
                             busy: [DateInterval] = [], calendar: Calendar = .current) -> DayPlan {
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
        // Only when the dip is ahead and low enough to be worth it — and in a slot
        // that isn't booked on the calendar.
        let napWorthwhile = dipAhead && dipLevel < 0.62
        let napDuration: TimeInterval = 30 * 60
        let ideal = max(dipTime.addingTimeInterval(-40 * 60), now)
        let suggestedNap: Date? = napWorthwhile
            ? freeSlot(ideal: ideal, duration: napDuration, busy: busy,
                       earliest: now, latest: dipTime.addingTimeInterval(30 * 60))
            : nil
        let napBlockedByCalendar = napWorthwhile && suggestedNap == nil && !busy.isEmpty

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
                       suggestedNap: suggestedNap, napBlockedByCalendar: napBlockedByCalendar,
                       items: items)
    }

    /// The free `duration`-long slot closest to `ideal` within `[earliest, latest]`
    /// that doesn't overlap any `busy` interval. Prefers earlier slots (nap *before*
    /// the dip) when equidistant. `nil` if the window is fully booked.
    static func freeSlot(ideal: Date, duration: TimeInterval, busy: [DateInterval],
                         earliest: Date, latest: Date) -> Date? {
        guard latest.timeIntervalSince(earliest) >= duration else { return nil }
        func isFree(_ start: Date) -> Bool {
            guard start >= earliest, start.addingTimeInterval(duration) <= latest else { return false }
            let slot = DateInterval(start: start, duration: duration)
            return !busy.contains { $0.intersects(slot) }
        }
        if isFree(ideal) { return ideal }
        let step: TimeInterval = 5 * 60
        var offset = step
        let span = latest.timeIntervalSince(earliest)
        while offset <= span {
            if isFree(ideal.addingTimeInterval(-offset)) { return ideal.addingTimeInterval(-offset) }
            if isFree(ideal.addingTimeInterval(offset)) { return ideal.addingTimeInterval(offset) }
            offset += step
        }
        return nil
    }
}
