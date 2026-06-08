//
//  NapHealthWriter.swift
//  SleepBank Watch App
//
//  Writes a completed nap to Apple Health as a sleep sample so SleepBank's naps
//  appear in Health alongside Apple's own records. We write the detected asleep
//  window (onset → wake) as `asleepUnspecified` — honest, since the watch-only
//  detector doesn't truly stage the nap.
//
//  Note: Apple Watch (watchOS 11+) may also record the same nap if it's above the
//  user's configured minimum nap duration, so this sample can overlap Apple's.
//  Ours is tagged (SleepBankNapType) so AppleSleepComparator excludes it when
//  comparing against Apple's detection. See RATIONALE.md §6.
//

import Foundation
import HealthKit
import SleepBankCore

final class NapHealthWriter {

    static let shared = NapHealthWriter()
    private let store = HKHealthStore()

    /// Save the nap's asleep window to Health. No-op if onset was never detected
    /// (no real sleep to record). Authorization is requested alongside the
    /// workout permissions in NapWorkoutService.
    func write(_ record: NapRecord) {
        guard HKHealthStore.isHealthDataAvailable(), let onset = record.onset, record.end > onset else { return }
        let type = HKCategoryType(.sleepAnalysis)
        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: onset,
            end: record.end,
            metadata: [
                HKMetadataKeyWasUserEntered: false,
                "SleepBankNapType": record.type.rawValue,
            ]
        )
        store.save(sample) { success, error in
            if let error { print("[NapHealthWriter] save failed: \(error.localizedDescription)") }
            else { print("[NapHealthWriter] wrote nap to Health: success=\(success)") }
        }
    }
}
