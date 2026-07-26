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
import WidgetKit
import SleepChartKit
import SleepBankCore

@Observable
class HealthKitService {

    static let shared = HealthKitService()

    let store = HKHealthStore()
    var isAuthorized = false
    /// iOS 27 lets users expose only a bounded slice of Health history. Keep the
    /// per-type lower bounds so every historical query honors that choice.
    private var earliestAuthorizedDates: [HKObjectType: Date] = [:]

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
            // Mood comorbidity context: depression/anxiety strongly affect sleep.
            // These are the only questionnaires Apple exposes natively (iOS 18+).
            HKScoredAssessmentType(.PHQ9),
            HKScoredAssessmentType(.GAD7),
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            do {
                earliestAuthorizedDates = try await store.earliestAuthorizedSampleDate(for: readTypes)
            } catch {
                // Authorization still succeeded. An empty map has the same
                // semantics as full-history access for query construction.
                earliestAuthorizedDates = [:]
                print("[HealthKit] Limited-history bounds unavailable: \(error)")
            }
            isAuthorized = true
            return true
        } catch {
            print("[HealthKit] Authorization error: \(error)")
            return false
        }
    }

    // MARK: - Mood assessments (read-only context)

    /// A PHQ-9 or GAD-7 result the user took in the Health app — reflected read-only
    /// as sleep comorbidity context. We don't administer or score these; Apple does.
    struct MoodAssessment: Identifiable {
        let id = UUID()
        let title: String     // "Depression (PHQ-9)" / "Anxiety (GAD-7)"
        let score: Int
        let scoreMax: Int
        let risk: String      // Apple's computed risk band
        let date: Date
    }

    /// Most recent PHQ-9 and GAD-7 the user has in Apple Health, if any.
    func latestMoodAssessments() async -> [MoodAssessment] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        var out: [MoodAssessment] = []
        if let phq = await latestSample(HKScoredAssessmentType(.PHQ9)) as? HKPHQ9Assessment {
            out.append(MoodAssessment(title: "Depression (PHQ-9)", score: phq.score, scoreMax: 27,
                                      risk: Self.riskLabel(phq.risk), date: phq.endDate))
        }
        if let gad = await latestSample(HKScoredAssessmentType(.GAD7)) as? HKGAD7Assessment {
            out.append(MoodAssessment(title: "Anxiety (GAD-7)", score: gad.score, scoreMax: 21,
                                      risk: Self.riskLabel(gad.risk), date: gad.endDate))
        }
        return out
    }

    private func latestSample(_ type: HKSampleType) async -> HKSample? {
        await withCheckedContinuation { cont in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                      sortDescriptors: sort) { _, samples, _ in
                cont.resume(returning: samples?.first)
            }
            store.execute(query)
        }
    }

    private static func riskLabel(_ r: HKPHQ9Assessment.Risk) -> String {
        switch r {
        case .noneToMinimal:    return "None–minimal"
        case .mild:             return "Mild"
        case .moderate:         return "Moderate"
        case .moderatelySevere: return "Moderately severe"
        case .severe:           return "Severe"
        @unknown default:       return "—"
        }
    }

    private static func riskLabel(_ r: HKGAD7Assessment.Risk) -> String {
        switch r {
        case .noneToMinimal: return "None–minimal"
        case .mild:          return "Mild"
        case .moderate:      return "Moderate"
        case .severe:        return "Severe"
        @unknown default:    return "—"
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
            // Mirror today's daylight to the App Group so the Daylight widget matches.
            SharedStore.daylightTotalMin = Int(daylightDay.total.rounded())
            SharedStore.daylightMorningMin = Int(daylightDay.morning.rounded())
            SharedStore.morningActivityMin = Int(morningExercise.rounded())
            SharedStore.morningLightStreak = streak
            SharedStore.lastRefreshAt = Date().timeIntervalSince1970
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// "Time in Daylight" samples (Apple Watch ambient-light metric, iOS 17+) over
    /// the last `days` days, as plain intervals for `Daylight` to bucket and streak.
    func fetchDaylight(days: Int) async -> [Daylight.Interval] {
        let type = HKQuantityType(.timeInDaylight)
        let requestedStart = Calendar.current.date(
            byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        let start = authorizedStart(for: type, requested: requestedStart)
        guard start < Date() else { return [] }
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
        let type = HKQuantityType(.appleExerciseTime)
        let start = authorizedStart(for: type, requested: wake)
        guard end > start else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type,
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

    /// The window for *last night's* sleep — yesterday evening (18:00) to this
    /// morning (noon, or now if earlier). With `.strictStartDate` (which filters by
    /// each sample's START), this cleanly takes only last night's session: the prior
    /// night's samples all start before 18:00 yesterday, and today's daytime naps
    /// start after noon — both excluded. (The old 00:00-yesterday start swept in the
    /// prior night's post-midnight hours, double-counting them into "last night.")
    private func lastNightWindow(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        nightWindow(ending: now, now: now, calendar: calendar)
    }

    /// The sleep window for the night ending on `morning` ([18:00 the day before, noon],
    /// capped at `now` when that morning is today).
    private func nightWindow(ending morning: Date, now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let startOfDay = calendar.startOfDay(for: morning)
        let eveningBefore = calendar.date(byAdding: .hour, value: -6, to: startOfDay) ?? startOfDay   // 18:00 prior day
        let noon = calendar.date(byAdding: .hour, value: 12, to: startOfDay) ?? startOfDay
        return (eveningBefore, calendar.isDate(startOfDay, inSameDayAs: now) ? min(now, noon) : noon)
    }

    /// Summary + stage samples for the night ending on `date` — powers History's
    /// per-day browsing.
    func sleep(nightEnding date: Date) async -> (summary: SleepSummary?, samples: [SleepSample]) {
        let window = nightWindow(ending: date)
        async let summary = fetchSleep(window: window)
        async let samples = fetchLastNightSamples(window: window)
        return await (summary, samples)
    }

    /// Raw sleep stages for a window, converted to SleepChartKit samples.
    func fetchLastNightSamples(window: (start: Date, end: Date)? = nil) async -> [SleepSample] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let window = window ?? lastNightWindow()
        let start = authorizedStart(for: sleepType, requested: window.start)
        guard start < window.end else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: window.end, options: .strictStartDate)
        guard let raw = try? await querySamples(sleepType, predicate: predicate) else { return [] }
        if #available(iOS 16.0, *) {
            return SleepSample.samples(from: raw)
        }
        return []
    }

    // MARK: - Sleep

    private func fetchSleep(window: (start: Date, end: Date)? = nil) async -> SleepSummary? {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let window = window ?? lastNightWindow()
        let start = authorizedStart(for: sleepType, requested: window.start)
        guard start < window.end else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: window.end, options: .strictStartDate)

        do {
            let samples = try await querySamples(sleepType, predicate: predicate)

            var asleep: TimeInterval = 0
            var rem: TimeInterval = 0, deep: TimeInterval = 0, core: TimeInterval = 0, awake: TimeInterval = 0
            // Track the in-bed span from the samples themselves — Apple Watch rarely
            // emits explicit `.inBed`, so bedtime/wake/in-bed come from the session.
            var sessionStart: Date?, sessionEnd: Date?

            for sample in samples {
                let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                let counts: Bool
                switch value {
                case .inBed, .asleepUnspecified, .asleep, .asleepREM, .asleepDeep, .asleepCore, .awake:
                    counts = true
                default: counts = false
                }
                guard counts else { continue }
                if sessionStart == nil || sample.startDate < sessionStart! { sessionStart = sample.startDate }
                if sessionEnd == nil || sample.endDate > sessionEnd! { sessionEnd = sample.endDate }

                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                switch value {
                case .asleepUnspecified, .asleep: asleep += duration
                case .asleepREM: rem += duration; asleep += duration
                case .asleepDeep: deep += duration; asleep += duration
                case .asleepCore: core += duration; asleep += duration
                case .awake: awake += duration
                default: break   // .inBed contributes to the span only
                }
            }

            let totalSleepHours = asleep / 3600
            // In bed = the whole session span (asleep + awake/restless in between).
            let inBedSeconds = (sessionStart != nil && sessionEnd != nil)
                ? sessionEnd!.timeIntervalSince(sessionStart!) : asleep
            let inBedHours = inBedSeconds / 3600
            let avg = await fetchSleepAverage7Day()

            return SleepSummary(
                totalHours: totalSleepHours,
                inBedHours: inBedHours,
                remHours: rem / 3600,
                deepHours: deep / 3600,
                coreHours: core / 3600,
                awakeHours: awake / 3600,
                bedtime: sessionStart,
                wakeTime: sessionEnd,
                efficiency: inBedSeconds > 0 ? min(asleep / inBedSeconds, 1) : 0,
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
        let start = authorizedStart(for: sleepType, requested: weekAgo)
        guard start < now else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        do {
            let samples = try await querySamples(sleepType, predicate: predicate)
            let totalSleep = samples.filter {
                switch HKCategoryValueSleepAnalysis(rawValue: $0.value) {
                case .asleepUnspecified, .asleep, .asleepREM, .asleepDeep, .asleepCore: return true
                default: return false
                }
            }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            // Don't divide a two-day authorized slice by seven; that would turn
            // privacy-limited history into an artificially poor sleep average.
            let authorizedDays = min(7, max(1, now.timeIntervalSince(start) / 86_400))
            return (totalSleep / 3600) / authorizedDays
        } catch {
            return 0
        }
    }

    /// Per-night bedtimes for the last `nights` nights, derived from historical sleep
    /// samples — so Sleep Score's bedtime-consistency factor works on day one instead
    /// of waiting to accumulate. Groups samples into sessions (split on >3 h gaps),
    /// keeps the substantial overnight ones, and reports each session's start keyed to
    /// the day it ends.
    func fetchBedtimeHistory(nights: Int = 14) async -> [(day: Date, bedtime: Date)] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let now = Date()
        guard let requestedStart = Calendar.current.date(byAdding: .day, value: -nights, to: now) else {
            return []
        }
        let start = authorizedStart(for: sleepType, requested: requestedStart)
        guard start < now,
              let raw = try? await querySamples(sleepType,
                  predicate: HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate))
        else { return [] }

        func isAsleep(_ s: HKCategorySample) -> Bool {
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .asleepUnspecified, .asleep, .asleepREM, .asleepDeep, .asleepCore: return true
            default: return false
            }
        }
        let inBed = raw.filter {
            switch HKCategoryValueSleepAnalysis(rawValue: $0.value) {
            case .inBed, .asleepUnspecified, .asleep, .asleepREM, .asleepDeep, .asleepCore, .awake: return true
            default: return false
            }
        }.sorted { $0.startDate < $1.startDate }

        // Coalesce into sessions; a gap > 3 h starts a new one.
        var sessions: [(start: Date, end: Date, asleep: TimeInterval)] = []
        for s in inBed {
            let dur = isAsleep(s) ? s.endDate.timeIntervalSince(s.startDate) : 0
            if var last = sessions.last, s.startDate.timeIntervalSince(last.end) < 3 * 3600 {
                last.end = max(last.end, s.endDate)
                last.asleep += dur
                sessions[sessions.count - 1] = last
            } else {
                sessions.append((s.startDate, s.endDate, dur))
            }
        }

        // Keep substantial overnight sessions (>3 h asleep), one bedtime per end-day.
        let cal = Calendar.current
        var byDay: [Date: Date] = [:]
        for session in sessions where session.asleep > 3 * 3600 {
            let day = cal.startOfDay(for: session.end)
            byDay[day] = byDay[day].map { min($0, session.start) } ?? session.start
        }
        return byDay.map { (day: $0.key, bedtime: $0.value) }.sorted { $0.day < $1.day }
    }

    // MARK: - Resting HR trend

    private func fetchRestingHRTrend() async -> String {
        let type = HKQuantityType(.restingHeartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let now = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let authorizedTwoWeeksAgo = authorizedStart(for: type, requested: twoWeeksAgo)
        let authorizedOneWeekAgo = authorizedStart(for: type, requested: oneWeekAgo)

        async let thisWeek = fetchAverage(type, unit: unit,
            predicate: HKQuery.predicateForSamples(withStart: authorizedOneWeekAgo, end: now))
        async let lastWeek = fetchAverage(type, unit: unit,
            predicate: HKQuery.predicateForSamples(withStart: authorizedTwoWeeksAgo, end: oneWeekAgo))

        let (tw, lw) = await (thisWeek, lastWeek)
        guard lw > 0 else { return "insufficient_data" }
        let delta = tw - lw
        if delta > 3 { return "rising" }
        if delta < -3 { return "falling" }
        return "stable"
    }

    // MARK: - Query helpers

    private func authorizedStart(for type: HKObjectType, requested: Date) -> Date {
        guard let lowerBound = earliestAuthorizedDates[type] else { return requested }
        return max(requested, lowerBound)
    }

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
        let requestedStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let start = authorizedStart(for: quantityType, requested: requestedStart)
        guard start < Date() else { return 0 }
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: Date(), options: .strictStartDate)
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
