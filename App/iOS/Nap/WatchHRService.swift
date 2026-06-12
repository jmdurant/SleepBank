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
    private(set) var lastUpdate: Date?
    private(set) var heartRateHistory: [HeartRateSample] = []

    /// Fresh HR only — nil if no reading in the last 10 s.
    var freshHeartRate: Int? {
        guard currentHeartRate > 0, let t = lastUpdate, Date().timeIntervalSince(t) <= 10 else { return nil }
        return currentHeartRate
    }

    /// True once readings are actually arriving from the watch.
    var isStreaming: Bool { freshHeartRate != nil }

    func requestStart() {
        requested = true
        heartRateHistory = []
        PhoneConnectivity.shared.requestWatchHR(true)
    }

    func requestStop() {
        requested = false
        PhoneConnectivity.shared.requestWatchHR(false)
    }

    /// Called when a forwarded reading arrives from the watch.
    func update(bpm: Int) {
        guard bpm > 0 else { return }
        currentHeartRate = bpm
        lastUpdate = Date()
        heartRateHistory.append(HeartRateSample(timestamp: Date(), bpm: bpm))
        if heartRateHistory.count > 240 { heartRateHistory.removeFirst() }
    }
}
