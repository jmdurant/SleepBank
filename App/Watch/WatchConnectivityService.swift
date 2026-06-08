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
    private var eegConfidence: Double?
    private var eegDeep = false
    private var eegAt: Date?
    private let freshness: TimeInterval = 10

    /// Fresh external HR/HRV, or nil if none has arrived recently.
    var freshExternalHR: Int? { fresh(externalHRAt) ? externalHR : nil }
    var freshExternalHRV: Double? { fresh(externalHRAt) ? externalHRV : nil }
    /// Fresh EEG onset signal forwarded from the phone's Muse pipeline.
    var freshEEGConfidence: Double? { fresh(eegAt) ? eegConfidence : nil }
    var freshEEGDeep: Bool { fresh(eegAt) ? eegDeep : false }

    private func fresh(_ at: Date?) -> Bool {
        guard let at else { return false }
        return Date().timeIntervalSince(at) <= freshness
    }

    /// Tell the phone a nap started/ended so it can connect and stream sensors.
    /// transferUserInfo is queued and wakes the phone even when backgrounded.
    func notifyNap(started: Bool) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(["napEvent": started ? "start" : "end"])
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
        DispatchQueue.main.async {
            if let bpm = message["liveHR"] as? Int {
                self.externalHR = bpm
                self.externalHRV = message["liveHRV"] as? Double
                self.externalHRAt = Date()
            }
            if let conf = message["eegOnset"] as? Double {
                self.eegConfidence = conf
                self.eegDeep = (message["eegDeep"] as? Bool) ?? false
                self.eegAt = Date()
            }
        }
    }
}
