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

    /// Forward the Muse EEG onset signal to the watch nap loop.
    func sendEEG(onsetConfidence: Double, deepApproaching: Bool) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["eegOnset": onsetConfidence, "eegDeep": deepApproaching],
                            replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Session control from the watch

    /// The watch told us a nap started/ended. On start, connect and stream the
    /// paired sensors so their data feeds the nap loop; on end, stand down.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let event = userInfo["napEvent"] as? String else { return }
        DispatchQueue.main.async {
            switch event {
            case "start":
                PolarH10Service.shared.autoConnect()
                MuseService.shared.startScanning()
                if NoiseService.shared.autoPlayDuringNap { NoiseService.shared.play() }
                LiveActivityManager.shared.start(
                    title: userInfo["type"] as? String ?? "Nap",
                    sessionStart: Date(),
                    state: Self.contentState(from: userInfo)
                )
            case "update":
                LiveActivityManager.shared.update(Self.contentState(from: userInfo))
            case "onset":
                // Asleep now — the sound has done its masking job; fade it out.
                NoiseService.shared.fadeOut()
                LiveActivityManager.shared.update(Self.contentState(from: userInfo))
            case "end":
                PolarH10Service.shared.disconnect()
                MuseService.shared.disconnect()
                NoiseService.shared.fadeOut()
                LiveActivityManager.shared.end()
            default:
                break
            }
        }
    }

    private static func contentState(from info: [String: Any]) -> NapActivityAttributes.ContentState {
        let wake = (info["wakeTarget"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        return NapActivityAttributes.ContentState(
            phase: info["phase"] as? String ?? "settling",
            wakeTarget: wake,
            heartRate: info["hr"] as? Int ?? 0,
            onsetDetected: info["onset"] as? Bool ?? false
        )
    }

    // MARK: - WCSessionDelegate (iOS requires all three lifecycle methods)

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for the next paired watch.
        WCSession.default.activate()
    }
}
