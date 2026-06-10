//
//  PlanSummary.swift
//  SleepBank (shared — watch app + watch complication)
//
//  A pure-Foundation digest of the day's plan that the watch app computes (it has
//  SleepBankCore) and writes to the App Group, so the watch complication — which
//  does NOT link SleepBankCore — can show the next thing to do without recomputing
//  the rhythm. Item times are absolute, so the complication can pick the *current*
//  next action at each timeline entry.
//

import Foundation

struct PlanSummary: Codable {
    struct Item: Codable {
        let kind: String      // DayPlan.Kind raw value
        let time: Date?       // nil = "now"
        let done: Bool
    }

    let startPct: Int
    let isShortNight: Bool
    let items: [Item]

    /// The next thing to do at `now`: the first not-done item that's either "now"
    /// (no time) or still ahead; falls back to the last unfinished item.
    func next(at now: Date) -> Item? {
        items.first { !$0.done && ($0.time.map { $0 >= now } ?? true) }
            ?? items.last { !$0.done }
    }
}
