//
//  PhoneConnectivity.swift
//  SleepBank
//
//  Phone side of the watch link. Pushes the latest last-night sleep timeline to
//  the watch as application context (the latest-value channel — the watch gets
//  the most recent payload whenever it's reachable, which is exactly the
//  semantics we want for "last night").
//

import Foundation
import WatchConnectivity
import SleepChartKit

@Observable
class PhoneConnectivity: NSObject, WCSessionDelegate {

    static let shared = PhoneConnectivity()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send last-night samples to the watch. Safe to call repeatedly; only the
    /// latest context is retained by the system.
    func sendLastNight(_ samples: [SleepSample]) {
        guard WCSession.default.activationState == .activated, !samples.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(samples.dtos) else { return }
        try? WCSession.default.updateApplicationContext(["lastNight": data])
    }

    /// Forward a live H10 reading to the watch's nap loop. Best-effort: only sent
    /// when the watch app is reachable (it is during a nap, kept alive by the
    /// workout session); otherwise the watch falls back to its own wrist HR.
    func sendLiveHR(bpm: Int, hrv: Double) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable, bpm > 0 else { return }
        session.sendMessage(["liveHR": bpm, "liveHRV": hrv], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate (iOS requires all three lifecycle methods)

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for the next paired watch.
        WCSession.default.activate()
    }
}
