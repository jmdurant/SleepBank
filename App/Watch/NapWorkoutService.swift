//
//  NapWorkoutService.swift
//  SleepBank Watch App
//
//  Harvested and adapted from SexKit's WorkoutService. Runs an HKWorkoutSession
//  purely to keep the watch sensors alive in the background and stream live
//  heart rate during a nap. Unlike the original it does NOT write any activity
//  sample — a nap is not a workout; the session is just our sensor keepalive.
//

import Foundation
import HealthKit
import WatchKit
import os

private let log = Logger(subsystem: "com.doctordurant.sleepbank.watchapp", category: "NapWorkoutService")

@Observable
class NapWorkoutService: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {

    var isActive: Bool = false
    var currentHeartRate: Int = 0
    var oxygenSaturation: Double = 0          // SpO2 percentage (0-100)
    var heartRateSamples: [HeartRateSample] = []
    var startTime: Date?

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let healthStore = HKHealthStore()

    func requestPermissions() {
        // We don't save a workout, but starting a session needs workoutType
        // share access; HR/SpO2 are read.
        let share: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.oxygenSaturation),
            HKObjectType.workoutType(),
        ]
        healthStore.requestAuthorization(toShare: share, read: read) { success, error in
            log.info("HealthKit auth: success=\(success), error=\(error?.localizedDescription ?? "none")")
        }
    }

    /// Begin a nap monitoring session. Keeps sensors hot via HKWorkoutSession.
    func start() throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            log.error("HealthKit not available on this device")
            return
        }

        let hrType = HKQuantityType(.heartRate)
        if healthStore.authorizationStatus(for: hrType) == .notDetermined {
            requestPermissions()
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor

        session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        builder = session?.associatedWorkoutBuilder()

        session?.delegate = self
        builder?.delegate = self
        builder?.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: config
        )
        builder?.addMetadata([HKMetadataKeyWorkoutBrandName: "SleepBank"]) { _, _ in }

        let start = Date()
        session?.startActivity(with: start)
        builder?.beginCollection(withStart: start) { success, error in
            log.info("beginCollection: success=\(success), error=\(error?.localizedDescription ?? "none")")
        }

        startTime = start
        isActive = true
        WKInterfaceDevice.current().play(.start)
    }

    /// End the nap session. Discards the workout — we never persist it as exercise.
    func stop() {
        session?.end()
        isActive = false
        WKInterfaceDevice.current().play(.success)
    }

    // MARK: - HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        log.info("Nap session state: \(fromState.rawValue) → \(toState.rawValue)")
        if toState == .ended {
            builder?.endCollection(withEnd: date) { _, _ in
                // Discard rather than finishWorkout(): a nap is not a saved workout.
                self.builder?.discardWorkout()
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        log.error("Nap session failed: \(error.localizedDescription)")
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            if quantityType == HKQuantityType(.heartRate) {
                let bpm = workoutBuilder.statistics(for: quantityType)?
                    .mostRecentQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
                DispatchQueue.main.async {
                    self.currentHeartRate = Int(bpm)
                    self.heartRateSamples.append(HeartRateSample(timestamp: Date(), bpm: Int(bpm)))
                }
            }

            if quantityType == HKQuantityType(.oxygenSaturation) {
                let spo2 = workoutBuilder.statistics(for: quantityType)?
                    .mostRecentQuantity()?
                    .doubleValue(for: .percent()) ?? 0
                DispatchQueue.main.async {
                    self.oxygenSaturation = spo2 * 100
                }
            }
        }
    }
}
