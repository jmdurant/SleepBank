//
//  WatchHRRelay.swift
//  SleepBank Watch App
//
//  Lets a *phone* nap use the Apple Watch as a live sensor: wrist **heart rate**
//  (via a brief, never-saved workout session) and wrist **motion** (CoreMotion —
//  movement intensity + stillness, the stronger onset signal for a phone that's
//  sitting on a nightstand). Both are forwarded to the phone over WCSession every
//  couple of seconds while requested.
//
//  Note: the watch app must be reachable for the phone to start this (WCSession can't
//  cold-launch a watch workout); otherwise the phone falls back to its own sensors.
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
    private let motion = MotionService()
    private var latestHR = 0
    private var latestHRAt: Date?
    private var timer: Timer?
    private var restartRequested = false

    func start() {
        guard !isActive else { return }
        // A new request can arrive while the previous HealthKit session ends.
        guard session == nil else { restartRequested = true; return }
        restartRequested = false
        isActive = true
        latestHR = 0
        latestHRAt = nil
        motion.startMonitoring()
        startWorkout()   // for HR; motion works regardless
        // Forward HR + wrist motion to the phone on a steady cadence.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            WatchConnectivityService.shared.sendWatchSensors(
                bpm: self.latestHR, heartRateAt: self.latestHRAt, motionAt: self.motion.lastUpdate,
                movement: self.motion.movementIntensity,
                stillSeconds: self.motion.stillSeconds)
        }
    }

    func stop() {
        restartRequested = false
        timer?.invalidate(); timer = nil
        motion.stopMonitoring()
        session?.end()
        isActive = false
        latestHR = 0
        latestHRAt = nil
    }

    private func startWorkout() {
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
        } catch {
            print("[WatchHRRelay] workout start failed: \(error)")
        }
    }

    // MARK: - Delegates

    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState,
                        from: HKWorkoutSessionState, date: Date) {
        if to == .ended {
            DispatchQueue.main.async {
                guard s === self.session else { return }
                let completedBuilder = self.builder
                let shouldRestart = self.restartRequested
                self.session = nil
                self.builder = nil
                self.stop()
                completedBuilder?.endCollection(withEnd: date) { _, _ in completedBuilder?.discardWorkout() }
                if shouldRestart { self.start() }
            }
        }
    }

    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            guard s === self.session else { return }
            self.stop()
            self.builder?.discardWorkout()
            self.builder = nil
            self.session = nil
        }
    }
    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        guard types.contains(HKQuantityType(.heartRate)) else { return }
        let statistics = b.statistics(for: HKQuantityType(.heartRate))
        let bpm = statistics?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
        guard bpm.isFinite, bpm > 0, let at = statistics?.mostRecentQuantityDateInterval()?.end else { return }
        DispatchQueue.main.async {
            guard self.isActive, b === self.builder,
                  RelayTimestamp.accepts(at, after: self.latestHRAt) else { return }
            self.latestHR = Int(bpm)
            self.latestHRAt = at
        }
    }
}
