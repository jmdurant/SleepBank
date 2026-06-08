//
//  NapHealthWriter.swift
//  SleepBank Watch App
//
//  Writes a completed nap to Apple Health as a sleep sample. This matters most
//  for short power naps: Apple's own nap detection ignores sleep periods under an
//  hour, so without this the 20-minute nap never appears in Health. We write the
//  detected asleep window (onset → wake) as `asleepUnspecified` — honest, since
//  the watch-only detector doesn't truly stage the nap.
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
