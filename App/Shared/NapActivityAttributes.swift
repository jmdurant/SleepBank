//
//  NapActivityAttributes.swift
//  SleepBank (shared — iOS app + widget extension)
//
//  The data model for the nap Live Activity. Guarded on ActivityKit so this file
//  also compiles harmlessly into the watch target (watchOS has no ActivityKit).
//  Phase is carried as a raw string so the widget extension stays light and
//  doesn't need SleepBankCore.
//

#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct NapActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String          // NapPhase.rawValue
        var wakeTarget: Date?      // for the live countdown
        var heartRate: Int
        var onsetDetected: Bool
    }

    var napTitle: String           // "Power Nap" / "Cycle Nap"
    var sessionStart: Date
}
#endif
