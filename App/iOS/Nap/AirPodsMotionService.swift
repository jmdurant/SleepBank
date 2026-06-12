//
//  AirPodsMotionService.swift
//  SleepBank
//
//  Head-stillness from AirPods (Pro/Max, 3rd-gen+) via CMHeadphoneMotionManager.
//  In the AirPods-only nap config the phone usually sits on a nightstand, so its
//  own accelerometer is a near-useless immobility signal — but the AirPods are on
//  the user's head, so their motion is the real actigraphy half of onset detection
//  (head still AND heart rate dropped → probably asleep).
//
//  Mirrors App/Shared/MotionService.swift: a normalized 0–1 movement intensity plus
//  a running "still for N seconds" tracker. Source here is device motion
//  (userAcceleration + rotationRate, gravity already removed) rather than raw
//  accelerometer, so no 1.0g subtraction is needed.
//

import Foundation
import CoreMotion

@Observable
final class AirPodsMotionService {

    static let shared = AirPodsMotionService()

    private(set) var movementIntensity: Double = 0   // 0.0 - 1.0
    private(set) var isMoving = false
    /// Continuous seconds the head has been below the stillness threshold.
    private(set) var stillSeconds: TimeInterval = 0
    private(set) var lastUpdate: Date?
    private(set) var isAvailable = false

    /// Below this normalized intensity we consider the head "still".
    private let stillnessThreshold = 0.05

    private let manager = CMHeadphoneMotionManager()
    private var recent: [Double] = []
    private let sampleWindow = 20

    /// Fresh stillness only — nil if no head-motion sample in the last 10 s, so the
    /// nap loop can fall back to phone motion rather than trust a stale reading
    /// (AirPods drop out of motion when removed from the ears).
    var freshStillSeconds: TimeInterval? {
        guard let t = lastUpdate, Date().timeIntervalSince(t) <= 10 else { return nil }
        return stillSeconds
    }
    var freshMovement: Double? {
        guard let t = lastUpdate, Date().timeIntervalSince(t) <= 10 else { return nil }
        return movementIntensity
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        recent = []
        stillSeconds = 0
        lastUpdate = nil
        isAvailable = true
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            // Translational head motion (gravity already removed) plus rotational
            // motion — either kind of head movement counts as "not still".
            let a = motion.userAcceleration
            let accel = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let r = motion.rotationRate
            let rot = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            let movement = accel + rot * 0.15   // weight rotation (rad/s) into g-scale

            self.recent.append(movement)
            if self.recent.count > self.sampleWindow { self.recent.removeFirst() }
            let avg = self.recent.reduce(0, +) / Double(self.recent.count)

            self.movementIntensity = min(avg / 0.5, 1.0)   // 0.5g-equiv+ = max
            self.isMoving = avg > self.stillnessThreshold

            let now = Date()
            let dt = self.lastUpdate.map { now.timeIntervalSince($0) } ?? 0
            self.lastUpdate = now
            if self.isMoving { self.stillSeconds = 0 } else { self.stillSeconds += dt }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        movementIntensity = 0
        isMoving = false
        stillSeconds = 0
        recent = []
        lastUpdate = nil
        isAvailable = false
    }
}
