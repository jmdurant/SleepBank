//
//  WatchHRRelay.swift
//  SleepBank Watch App
//
//  Lets a *phone* nap use the Apple Watch's wrist heart rate. The phone asks the
//  watch (over WCSession) to start a lightweight workout session purely to read HR,
//  and the watch forwards each reading back to the phone. We never save the workout
//  (discard on end). This is the watch→phone counterpart of the phone's H10/AirPods
//  HR — the Watch becomes a live HR sensor for phone-side naps.
//
//  Note: the watch app must be reachable for the phone to start this (WCSession can't
//  cold-launch a watch workout); when it isn't, the phone simply falls back to its
//  own sensors.
//

import Foundation
import HealthKit

@Observable
final class WatchHRRelay: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WatchHRRelay()

    private(set) var isActive = false
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let healthStore = HKHealthStore()

    func start() {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let b = s.associatedWorkoutBuilder()
            s.delegate = self
            b.delegate = self
            b.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            let now = Date()
            s.startActivity(with: now)
            b.beginCollection(withStart: now) { _, _ in }
            session = s
            builder = b
            isActive = true
        } catch {
            print("[WatchHRRelay] start failed: \(error)")
        }
    }

    func stop() {
        session?.end()
        isActive = false
    }

    // MARK: - Delegates

    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState,
                        from: HKWorkoutSessionState, date: Date) {
        if to == .ended {
            builder?.endCollection(withEnd: date) { [weak self] _, _ in
                self?.builder?.discardWorkout()
                self?.session = nil
                self?.builder = nil
            }
        }
    }

    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) { isActive = false }
    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        guard types.contains(HKQuantityType(.heartRate)) else { return }
        let bpm = b.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
        guard bpm > 0 else { return }
        WatchConnectivityService.shared.sendWatchHR(Int(bpm))
    }
}
