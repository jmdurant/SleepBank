//
//  PhoneWorkoutHRService.swift
//  SleepBank
//
//  Phone-side live heart rate via a primary HKWorkoutSession — the iOS 26 API that
//  makes the "AirPulse trick" first-class: starting a workout session on the iPhone
//  engages connected heart-rate sources (notably AirPods Pro) and streams live HR
//  through HKLiveWorkoutBuilder. We never persist the workout — `discardWorkout()`
//  drops it entirely, so the user's Activity/Health stays clean (cleaner than
//  save-then-delete). It also keeps the nap's sensors hot, like the watch session.
//
//  Mirrors App/Watch/NapWorkoutService.swift (minus the WatchKit haptics). All of
//  HKWorkoutSession(healthStore:configuration:), associatedWorkoutBuilder, and
//  HKLiveWorkoutDataSource are API_AVAILABLE(ios(26.0)).
//

import Foundation
import HealthKit
import os

private let log = Logger(subsystem: "com.doctordurant.sleepbank", category: "PhoneWorkoutHR")

@Observable
final class PhoneWorkoutHRService: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {

    private(set) var isActive = false
    private(set) var currentHeartRate = 0      // bpm, 0 until first reading
    private(set) var lastUpdate: Date?

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let healthStore = HKHealthStore()

    /// Fresh HR only — nil if no reading in the last 10 s (so the nap loop can fall
    /// back to another source rather than trust a stale value).
    var freshHeartRate: Int? {
        guard currentHeartRate > 0, let t = lastUpdate, Date().timeIntervalSince(t) <= 10 else { return nil }
        return currentHeartRate
    }

    func requestPermissions() {
        // Starting a session needs workoutType share access; HR is read. We never
        // save the workout, but the API still requires share auth to open a session.
        let share: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: share, read: read) { ok, err in
            log.info("workout HR auth: \(ok), \(err?.localizedDescription ?? "none")")
        }
    }

    /// Start a primary workout session to pull live HR (e.g. from AirPods Pro).
    func start() {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        if healthStore.authorizationStatus(for: HKQuantityType.workoutType()) == .notDetermined {
            requestPermissions()
        }
        cleanupStrayWorkouts()   // clear any leftover from a prior crashed session
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody     // a nap, not exercise
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self
            builder.delegate = self
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            builder.addMetadata([HKMetadataKeyWorkoutBrandName: "SleepBank"]) { _, _ in }
            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { ok, err in
                log.info("beginCollection: \(ok), \(err?.localizedDescription ?? "none")")
            }
            self.session = session
            self.builder = builder
            isActive = true
        } catch {
            log.error("workout session start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        session?.end()       // delegate discards the (unsaved) workout on .ended
        isActive = false
    }

    /// Safety net: we never intentionally persist a workout (we discard), so ANY
    /// `.mindAndBody` workout from our own app source is a stray left by a crash /
    /// force-quit mid-nap. Find and delete them. Safe to call on launch and at nap
    /// start. (HealthKit only lets an app delete samples it created.)
    func cleanupStrayWorkouts() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let mine = HKQuery.predicateForObjects(from: .default())
        let mindBody = HKQuery.predicateForWorkouts(with: .mindAndBody)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [mine, mindBody])
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, samples, _ in
            guard let self, let strays = samples, !strays.isEmpty else { return }
            self.healthStore.delete(strays) { ok, err in
                log.info("deleted \(strays.count) stray workout(s): \(ok), \(err?.localizedDescription ?? "none")")
            }
        }
        healthStore.execute(query)
    }

    // MARK: - HKWorkoutSessionDelegate

    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState,
                        from: HKWorkoutSessionState, date: Date) {
        if to == .ended {
            builder?.endCollection(withEnd: date) { [weak self] _, _ in
                self?.builder?.discardWorkout()   // never persist a nap as a workout
                self?.session = nil
                self?.builder = nil
            }
        }
    }

    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        log.error("workout session failed: \(error.localizedDescription)")
        isActive = false
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        guard types.contains(HKQuantityType(.heartRate)) else { return }
        let bpm = b.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
        guard bpm > 0 else { return }
        DispatchQueue.main.async {
            self.currentHeartRate = Int(bpm)
            self.lastUpdate = Date()
        }
    }
}
