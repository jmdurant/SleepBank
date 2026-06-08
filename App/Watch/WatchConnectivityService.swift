//
//  WatchConnectivityService.swift
//  SleepBank Watch App
//
//  Watch side of the link. Receives the phone's last-night sleep timeline via
//  application context and republishes it as SleepSamples for the chart.
//

import Foundation
import WatchConnectivity
import SleepChartKit

@Observable
class WatchConnectivityService: NSObject, WCSessionDelegate {

    static let shared = WatchConnectivityService()

    var lastNightSamples: [SleepSample] = []

    /// Latest live H10 reading forwarded from the phone, with arrival time so the
    /// nap loop can ignore stale data and fall back to wrist HR.
    private var externalHR: Int?
    private var externalHRV: Double?
    private var externalHRAt: Date?
    private let freshness: TimeInterval = 10

    /// Fresh external HR, or nil if none has arrived recently.
    var freshExternalHR: Int? { isFresh ? externalHR : nil }
    var freshExternalHRV: Double? { isFresh ? externalHRV : nil }
    private var isFresh: Bool {
        guard let at = externalHRAt else { return false }
        return Date().timeIntervalSince(at) <= freshness
    }

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func decode(_ context: [String: Any]) {
        guard let data = context["lastNight"] as? Data,
              let dtos = try? JSONDecoder().decode([SleepSampleDTO].self, from: data) else { return }
        DispatchQueue.main.async {
            self.lastNightSamples = dtos.sleepSamples
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        // Pick up the most recent context the phone already sent.
        decode(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        decode(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let bpm = message["liveHR"] as? Int else { return }
        let hrv = message["liveHRV"] as? Double
        DispatchQueue.main.async {
            self.externalHR = bpm
            self.externalHRV = hrv
            self.externalHRAt = Date()
        }
    }
}
