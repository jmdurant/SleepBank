//
//  AppleSleepComparator.swift
//  SleepBank
//
//  Compares our nap decision against Apple's own retrospective sleep staging for
//  the same window. Crucially it EXCLUDES the sample we wrote ourselves
//  (NapHealthWriter tags it), so we're really comparing against Apple's
//  detector. For sub-1-hour naps Apple records nothing — which is itself the
//  finding (Apple ignores short naps; we don't).
//

import Foundation
import HealthKit
import SleepBankCore

struct AppleNapComparison {
    var appleRecorded: Bool          // did Apple log any sleep for this window?
    var appleAsleepMinutes: Int
    var appleOnset: Date?
    var ourAsleepMinutes: Int
    var ourOnset: Date?

    /// Difference in detected onset (ours − Apple's), seconds. Positive = we
    /// detected onset later than Apple.
    var onsetDeltaSeconds: TimeInterval? {
        guard let a = appleOnset, let o = ourOnset else { return nil }
        return o.timeIntervalSince(a)
    }
}

final class AppleSleepComparator {

    private let store = HKHealthStore()

    func compare(_ record: NapDecisionRecord) async -> AppleNapComparison {
        let ours = AppleNapComparison(
            appleRecorded: false, appleAsleepMinutes: 0, appleOnset: nil,
            ourAsleepMinutes: record.asleepMinutes, ourOnset: record.onset
        )
        guard HKHealthStore.isHealthDataAvailable() else { return ours }

        // Widen the window to catch Apple's processing latency at the tail.
        let predicate = HKQuery.predicateForSamples(
            withStart: record.start.addingTimeInterval(-300),
            end: record.end.addingTimeInterval(1800),
            options: []
        )
        let samples = (try? await query(predicate)) ?? []

        // Apple's genuine asleep samples only — drop the one we wrote.
        let appleAsleep = samples.filter { sample in
            sample.metadata?["SleepBankNapType"] == nil && isAsleep(sample.value)
        }
        guard !appleAsleep.isEmpty else { return ours }

        let seconds = appleAsleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let onset = appleAsleep.map(\.startDate).min()
        var result = ours
        result.appleRecorded = true
        result.appleAsleepMinutes = Int(seconds / 60)
        result.appleOnset = onset
        return result
    }

    private func isAsleep(_ value: Int) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .asleepUnspecified, .asleep, .asleepREM, .asleepDeep, .asleepCore: return true
        default: return false
        }
    }

    private func query(_ predicate: NSPredicate) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: results as? [HKCategorySample] ?? []) }
            }
            store.execute(q)
        }
    }
}
