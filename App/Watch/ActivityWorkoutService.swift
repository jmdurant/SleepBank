//
//  ActivityWorkoutService.swift
//  SleepBank Watch App
//
//  Starts a *real, saved* workout (walking or general strength) when a scheduled
//  reminder's "Start Walk / Start Workout" action fires on the phone and the watch is
//  reachable. Distinct from NapWorkoutService, which runs a discarded mind-and-body
//  session just to keep nap sensors hot.
//
//  NOTE: the phone→watch start path needs verifying on a real paired watch.
//

import Foundation
import HealthKit
import WatchKit
import SwiftUI
import os

@Observable
final class ActivityWorkoutService: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = ActivityWorkoutService()

    private let log = Logger(subsystem: "SleepBank", category: "ActivityWorkout")
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var isActive = false
    var title = ""
    var startedAt: Date?

    func start(kind: String) {
        guard HKHealthStore.isHealthDataAvailable(), !isActive else { return }
        let isWalk = kind.caseInsensitiveCompare("walk") == .orderedSame
        title = isWalk ? "Walk" : "Workout"

        healthStore.requestAuthorization(
            toShare: [HKQuantityType.workoutType()],
            read: [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.begin(isWalk: isWalk) }
        }
    }

    private func begin(isWalk: Bool) {
        let config = HKWorkoutConfiguration()
        config.activityType = isWalk ? .walking : .functionalStrengthTraining
        config.locationType = isWalk ? .outdoor : .indoor
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
            session?.delegate = self
            builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            let now = Date()
            session?.startActivity(with: now)
            builder?.beginCollection(withStart: now) { _, _ in }
            startedAt = now
            isActive = true
            WKInterfaceDevice.current().play(.start)
        } catch {
            log.error("workout start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isActive else { return }
        session?.end()
        let end = Date()
        builder?.endCollection(withEnd: end) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        isActive = false
        startedAt = nil
        WKInterfaceDevice.current().play(.stop)
    }

    func workoutSession(_ s: HKWorkoutSession, didChangeTo: HKWorkoutSessionState, from: HKWorkoutSessionState, date: Date) {}
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        log.error("workout session error: \(error.localizedDescription)")
        DispatchQueue.main.async { self.isActive = false }
    }
    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}
    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}

/// Shown while an activity workout is running, with an End button.
struct WorkoutRunningView: View {
    var service = ActivityWorkoutService.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: service.title == "Walk" ? "figure.walk" : "figure.run")
                .font(.largeTitle).foregroundStyle(.green)
            Text("\(service.title) in progress").font(.headline)
            if let started = service.startedAt {
                Text(started, style: .timer).font(.title2.monospacedDigit())
            }
            Button(role: .destructive) { service.stop() } label: {
                Label("End", systemImage: "stop.fill")
            }
            .tint(.red)
        }
        .padding()
    }
}
