//
//  MotionService.swift
//  SleepBank Watch App
//
//  Harvested from SexKit's MotionService. Repurposed for sleep-onset work:
//  the original tracked rhythmic movement; here the signal we care about is the
//  opposite — sustained *stillness*. We keep the normalized movement intensity
//  and add a running "still for N seconds" tracker, which is the actigraphy
//  half of the onset detector (still AND heart-rate dropped → probably asleep).
//

import Foundation
import CoreMotion

@Observable
class MotionService {

    var movementIntensity: Double = 0   // 0.0 - 1.0
    var isMoving: Bool = false
    /// Continuous seconds the wrist has been below the stillness threshold.
    var stillSeconds: TimeInterval = 0

    /// Below this normalized intensity we consider the wrist "still".
    private let stillnessThreshold = 0.05

    private let motionManager = CMMotionManager()
    private var recentAccelerations: [Double] = []
    private let sampleWindow = 20
    private var lastUpdate: Date?

    func startMonitoring() {
        guard motionManager.isAccelerometerAvailable else { return }

        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }

            let magnitude = sqrt(
                data.acceleration.x * data.acceleration.x +
                data.acceleration.y * data.acceleration.y +
                data.acceleration.z * data.acceleration.z
            )
            let movement = abs(magnitude - 1.0)   // subtract gravity (1.0g)

            self.recentAccelerations.append(movement)
            if self.recentAccelerations.count > self.sampleWindow {
                self.recentAccelerations.removeFirst()
            }
            let avg = self.recentAccelerations.reduce(0, +) / Double(self.recentAccelerations.count)

            self.movementIntensity = min(avg / 0.5, 1.0)   // 0.5g+ = max
            self.isMoving = avg > self.stillnessThreshold

            // Accumulate / reset stillness duration.
            let now = Date()
            let dt = self.lastUpdate.map { now.timeIntervalSince($0) } ?? 0
            self.lastUpdate = now
            if self.isMoving {
                self.stillSeconds = 0
            } else {
                self.stillSeconds += dt
            }
        }
    }

    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
        movementIntensity = 0
        isMoving = false
        stillSeconds = 0
        recentAccelerations = []
        lastUpdate = nil
    }
}
