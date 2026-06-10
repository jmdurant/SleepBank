//
//  BedtimeHistoryStore.swift
//  SleepBank
//
//  Rolling record of recent bedtimes so we can score Apple's third Sleep-Score
//  factor — bedtime *consistency* — which needs history we have to accumulate
//  ourselves (HealthKit gives last night's samples, not a regularity number). We
//  keep the last ~14 nights, one entry per calendar day, and expose last night's
//  bedtime plus the "normal" (median of the prior nights) for SleepScore.
//

import Foundation

@Observable
final class BedtimeHistoryStore {
    static let shared = BedtimeHistoryStore()

    /// One night: the calendar day it belongs to and the bedtime expressed as
    /// minutes from a 6 PM anchor (so evening-into-morning is monotonic — 23:00 = 300,
    /// 00:30 = 390 — and the median needs no circular math).
    struct Entry: Codable, Equatable { var day: Double; var minutes: Int }

    private(set) var entries: [Entry] {
        didSet { persist() }
    }

    private static let key = "bedtimeHistory"
    private static let maxNights = 14
    /// Need a few nights before "normal" means anything.
    private static let minNightsForNormal = 3

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    /// Minutes from the 6 PM anchor for a wall-clock time.
    static func minutesFrom6pm(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let mins = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return (mins - 18 * 60 + 1440) % 1440
    }

    /// Record a night's bedtime, keyed to the day it ends (one entry per day, newest
    /// wins), trimmed to the rolling window.
    func record(bedtime: Date, on day: Date = Date()) {
        let stamp = Calendar.current.startOfDay(for: day).timeIntervalSinceReferenceDate
        var next = entries.filter { $0.day != stamp }
        next.append(Entry(day: stamp, minutes: Self.minutesFrom6pm(bedtime)))
        next.sort { $0.day < $1.day }
        entries = Array(next.suffix(Self.maxNights))
    }

    /// Last night's bedtime in anchor-minutes, if recorded.
    var lastNightMinutes: Int? { entries.last?.minutes }

    /// The "normal" bedtime — median of the prior nights (excluding the most recent,
    /// so last night is compared *against* its baseline, not itself). Nil until we
    /// have enough history.
    var normalMinutes: Int? {
        let prior = entries.dropLast().map(\.minutes).sorted()
        guard prior.count >= Self.minNightsForNormal else { return nil }
        let mid = prior.count / 2
        return prior.count.isMultiple(of: 2) ? (prior[mid - 1] + prior[mid]) / 2 : prior[mid]
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
