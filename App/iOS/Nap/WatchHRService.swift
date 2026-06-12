//
//  WatchHRService.swift
//  SleepBank
//
//  The Apple Watch as a live HR sensor for a *phone* nap. The phone asks the watch
//  (over WCSession) to start a wrist-HR workout and forward readings; this holds the
//  latest value. The best always-on HR source when there's no chest strap.
//
//  Reachability caveat: the watch app must be running to start the relay (WCSession
//  can't cold-launch a watch workout). When it isn't, freshHeartRate stays nil and
//  the nap falls back to its other sensors.
//

import Foundation

@Observable
final class WatchHRService {
    static let shared = WatchHRService()

    private(set) var requested = false        // we asked the watch to relay
    private(set) var currentHeartRate = 0
    private(set) var movementIntensity = 0.0  // wrist movement (0…1)
    private(set) var stillSeconds = 0.0       // wrist stillness
    private(set) var heartRateHistory: [HeartRateSample] = []
    private var lastHRAt: Date?
    private var lastMotionAt: Date?

    private func fresh(_ at: Date?) -> Bool {
        guard let at else { return false }
        return Date().timeIntervalSince(at) <= 10
    }

    /// Fresh HR — nil if no reading in the last 10 s.
    var freshHeartRate: Int? { (currentHeartRate > 0 && fresh(lastHRAt)) ? currentHeartRate : nil }
    /// Fresh wrist motion — the immobility signal for a phone nap.
    var freshMovement: Double? { fresh(lastMotionAt) ? movementIntensity : nil }
    var freshStillSeconds: Double? { fresh(lastMotionAt) ? stillSeconds : nil }

    /// True once readings are actually arriving from the watch.
    var isStreaming: Bool { freshHeartRate != nil || fresh(lastMotionAt) }

    func requestStart() {
        requested = true
        heartRateHistory = []
        PhoneConnectivity.shared.requestWatchHR(true)
    }

    func requestStop() {
        requested = false
        PhoneConnectivity.shared.requestWatchHR(false)
    }

    /// Called when a forwarded reading (HR + wrist motion) arrives from the watch.
    func update(bpm: Int, movement: Double?, stillSeconds: Double?) {
        let now = Date()
        if bpm > 0 {
            currentHeartRate = bpm
            lastHRAt = now
            heartRateHistory.append(HeartRateSample(timestamp: now, bpm: bpm))
            if heartRateHistory.count > 240 { heartRateHistory.removeFirst() }
        }
        if let movement { movementIntensity = movement; lastMotionAt = now }
        if let stillSeconds { self.stillSeconds = stillSeconds; lastMotionAt = now }
    }
}
