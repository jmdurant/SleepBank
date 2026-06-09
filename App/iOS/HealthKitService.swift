//
//  HealthKitService.swift
//  SleepBank
//
//  Harvested from SexKit and trimmed to what a nap app needs: authorization,
//  last-night sleep summary + 7-day average, resting HR and its trend, and HRV.
//  This is our source of *retrospective* truth — Apple writes sleep stages after
//  the fact, so we use this to calibrate the live on-wrist onset detector and to
//  give the phone-side a baseline context for the day's naps.
//

import Foundation
import HealthKit
import SleepChartKit
import SleepBankCore

@Observable
class HealthKitService {

    static let shared = HealthKitService()

    let store = HKHealthStore()
    var isAuthorized = false

    /// Real last-night stage samples, ready for SleepChartKit. Empty until fetched.
    var lastNightSamples: [SleepSample] = []
    var lastNightSleep: SleepSummary?
    var sleepAverage7Day: Double = 0          // hours
    var restingHeartRate: Double = 0          // bpm
    var restingHRTrend: String = "stable"     // rising, falling, stable
    var hrvAverage: Double = 0                // ms (SDNN)
    /// Today's daylight, split into morning / afternoon / evening windows.
    var daylightToday: DaylightDay = .empty
    /// Consecutive days with morning daylight — the "morning light" habit streak.
    var morningLightStreak: Int = 0
    /// Minutes of exercise in this morning's window (drives the movement credit).
    var morningActivityMinutes: Double = 0
    var lastRefresh: Date?

    struct SleepSummary {
        var totalHours: Double
        var inBedHours: Double
        var remHours: Double
        var deepHours: Double
        var coreHours: Double
        var awakeHours: Double
        var bedtime: Date?
        var wakeTime: Date?
        var efficiency: Double                // asleep / in-bed
        var averageLast7Days: Double
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        let readTypes: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.heartRate),
            HKQuantityType(.timeInDaylight),
            HKQuantityType(.appleExerciseTime),
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            return true
        } catch {
            print("[HealthKit] Authorization error: \(error)")
            return false
        }
    }

    // MARK: - Refresh

    func refreshAll() async {
        guard isAuthorized else { return }

        async let sleep = fetchSleep()
        async let samples = fetchLastNightSamples()
        async let rhr = fetchLatestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()))
        async let hrv = fetchLatestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let trend = fetchRestingHRTrend()
        async let daylight = fetchDaylight(days: 14)

        let (sleepResult, sampleResult, rhrVal, hrvVal, trendVal, daylightIntervals) =
            await (sleep, samples, rhr, hrv, trend, daylight)

        // Bucket daylight around today's wake time (default 7:00 if no sleep data).
        let wake = sleepResult?.wakeTime
            ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayIntervals = daylightIntervals.filter { $0.start >= todayStart }
        let daylightDay = DaylightDay.summarize(intervals: todayIntervals, wakeTime: wake)
        let streak = Daylight.morningStreak(intervals: daylightIntervals, asOf: Date())
        let morningExercise = await fetchMorningExerciseMinutes(wake: wake)

        await MainActor.run {
            lastNightSleep = sleepResult
            lastNightSamples = sampleResult
            restingHeartRate = rhrVal
            hrvAverage = hrvVal
            restingHRTrend = trendVal
            daylightToday = daylightDay
            morningLightStreak = streak
            morningActivityMinutes = morningExercise
            sleepAverage7Day = sleepResult?.averageLast7Days ?? 0
            lastRefresh = Date()
        }
    }

    /// "Time in Daylight" samples (Apple Watch ambient-light metric, iOS 17+) over
    /// the last `days` days, as plain intervals for `Daylight` to bucket and streak.
    func fetchDaylight(days: Int) async -> [Daylight.Interval] {
        let type = HKQuantityType(.timeInDaylight)
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, _ in
                let intervals = (results as? [HKQuantitySample] ?? []).map {
                    Daylight.Interval(start: $0.startDate, end: $0.endDate,
                                      minutes: $0.quantity.doubleValue(for: .minute()))
                }
                continuation.resume(returning: intervals)
            }
            store.execute(query)
        }
    }

    /// Minutes of Apple "Exercise Time" logged in this morning's window (wake → +4 h,
    /// capped at now) — the signal behind the morning-movement credit.
    func fetchMorningExerciseMinutes(wake: Date) async -> Double {
        let now = Date()
        let end = min(now, wake.addingTimeInterval(4 * 3600))
        guard end > wake else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: wake, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(.appleExerciseTime),
                                          quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: .minute()) ?? 0)
            }
            store.execute(query)
        }
    }

    /// Latest blood-oxygen saturation (%) from Health — spot-measured, so this is
    /// best-effort and often recent-but-not-live. Captured for completeness.
    func latestOxygenSaturation() async -> Double {
        await fetchLatestQuantity(.oxygenSaturation, unit: .percent()) * 100
    }

    /// Raw last-night sleep stages converted to SleepChartKit samples.
    func fetchLastNightSamples() async -> [SleepSample] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let startOfYesterday = Calendar.current.startOfDay(for: yesterday)
        let predicate = HKQuery.predicateForSamples(withStart: startOfYesterday, end: now, options: .strictStartDate)
        guard let raw = try? await querySamples(sleepType, predicate: predicate) else { return [] }
        if #available(iOS 16.0, *) {
            return SleepSample.samples(from: raw)
        }
        return []
    }

    // MARK: - Sleep

    private func fetchSleep() async -> SleepSummary? {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let startOfYesterday = Calendar.current.startOfDay(for: yesterday)
        let predicate = HKQuery.predicateForSamples(withStart: startOfYesterday, end: now, options: .strictStartDate)

        do {
            let samples = try await querySamples(sleepType, predicate: predicate)

            var inBed: TimeInterval = 0, asleep: TimeInterval = 0
            var rem: TimeInterval = 0, deep: TimeInterval = 0, core: TimeInterval = 0, awake: TimeInterval = 0
            var bedtime: Date?, wakeTime: Date?

            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .inBed:
                    inBed += duration
                    if bedtime == nil { bedtime = sample.startDate }
                    wakeTime = sample.endDate
                case .asleepUnspecified, .asleep: asleep += duration
                case .asleepREM: rem += duration; asleep += duration
                case .asleepDeep: deep += duration; asleep += duration
                case .asleepCore: core += duration; asleep += duration
                case .awake: awake += duration
                default: break
                }
            }

            let totalSleepHours = asleep / 3600
            let inBedHours = max(inBed, asleep) / 3600
            let avg = await fetchSleepAverage7Day()

            return SleepSummary(
                totalHours: totalSleepHours,
                inBedHours: inBedHours,
                remHours: rem / 3600,
                deepHours: deep / 3600,
                coreHours: core / 3600,
                awakeHours: awake / 3600,
                bedtime: bedtime,
                wakeTime: wakeTime,
                efficiency: inBedHours > 0 ? totalSleepHours / inBedHours : 0,
                averageLast7Days: avg
            )
        } catch {
            return nil
        }
    }

    private func fetchSleepAverage7Day() async -> Double {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let now = Date()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: now, options: .strictStartDate)

        do {
            let samples = try await querySamples(sleepType, predicate: predicate)
            let totalSleep = samples.filter {
                switch HKCategoryValueSleepAnalysis(rawValue: $0.value) {
                case .asleepUnspecified, .asleep, .asleepREM, .asleepDeep, .asleepCore: return true
                default: return false
                }
            }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            return (totalSleep / 3600) / 7.0
        } catch {
            return 0
        }
    }

    // MARK: - Resting HR trend

    private func fetchRestingHRTrend() async -> String {
        let type = HKQuantityType(.restingHeartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let now = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!

        async let thisWeek = fetchAverage(type, unit: unit,
            predicate: HKQuery.predicateForSamples(withStart: oneWeekAgo, end: now))
        async let lastWeek = fetchAverage(type, unit: unit,
            predicate: HKQuery.predicateForSamples(withStart: twoWeeksAgo, end: oneWeekAgo))

        let (tw, lw) = await (thisWeek, lastWeek)
        guard lw > 0 else { return "insufficient_data" }
        let delta = tw - lw
        if delta > 3 { return "rising" }
        if delta < -3 { return "falling" }
        return "stable"
    }

    // MARK: - Query helpers

    private func querySamples(_ type: HKCategoryType, predicate: NSPredicate) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: results as? [HKCategorySample] ?? []) }
            }
            store.execute(query)
        }
    }

    private func fetchLatestQuantity(_ type: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        let quantityType = HKQuantityType(type)
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: -7, to: Date()), end: Date(), options: .strictStartDate)
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: 1,
                                          sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, results, error in
                    if let error { continuation.resume(throwing: error); return }
                    if let sample = results?.first as? HKQuantitySample {
                        continuation.resume(returning: sample.quantity.doubleValue(for: unit))
                    } else {
                        continuation.resume(returning: 0)
                    }
                }
                store.execute(query)
            }
        } catch {
            return 0
        }
    }

    private func fetchAverage(_ type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async -> Double {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, error in
                    if let error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: result?.averageQuantity()?.doubleValue(for: unit) ?? 0)
                }
                store.execute(query)
            }
        } catch {
            return 0
        }
    }
}
