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
import WidgetKit
import SleepChartKit
import SleepBankCore

@Observable
class PhoneConnectivity: NSObject, WCSessionDelegate {

    static let shared = PhoneConnectivity()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send the daily summary to the watch — last-night samples plus the morning-
    /// light streak (for the watch complication). One application context, since the
    /// system keeps only the latest. Safe to call repeatedly.
    func sendDailySummary(samples: [SleepSample], morningLightStreak: Int, rhythmSnapshot: Data?) {
        guard WCSession.default.activationState == .activated else { return }
        var context: [String: Any] = ["morningLightStreak": morningLightStreak]
        if !samples.isEmpty, let data = try? JSONEncoder().encode(samples.dtos) {
            context["lastNight"] = data
        }
        if let rhythmSnapshot { context["rhythmSnapshot"] = rhythmSnapshot }
        // Carry the chosen wind-down guide so a watch-started nap can pace it on the wrist.
        context["relaxGuide"] = GuidedRelaxationService.shared.guide.rawValue
        try? WCSession.default.updateApplicationContext(context)
    }

    /// Forward a live H10 reading to the watch's nap loop. Best-effort: only sent
    /// when the watch app is reachable (it is during a nap, kept alive by the
    /// workout session); otherwise the watch falls back to its own wrist HR.
    func sendLiveHR(bpm: Int, hrv: Double) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable, bpm > 0 else { return }
        session.sendMessage(["liveHR": bpm, "liveHRV": hrv], replyHandler: nil, errorHandler: nil)
    }

    /// Ask the watch to start a real workout (walk / general) from a reminder's
    /// action button. Best-effort: `sendMessage` if the watch app is reachable, else
    /// queue it as application context for when it next wakes.
    func startWorkout(_ kind: String) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = ["startWorkout": kind, "ts": Date().timeIntervalSince1970]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in
                try? session.updateApplicationContext(payload)
            })
        } else {
            try? session.updateApplicationContext(payload)
        }
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
                SharedStore.napActive = true
                WidgetCenter.shared.reloadAllTimelines()
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
                SharedStore.napActive = false
                SharedStore.napsToday = userInfo["napsToday"] as? Int ?? SharedStore.napsToday
                SharedStore.minutesToday = userInfo["minutesToday"] as? Int ?? SharedStore.minutesToday
                WidgetCenter.shared.reloadAllTimelines()
            default:
                break
            }
        }
    }

    /// Receive a nap decision + trace file synced from the watch.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL),
              let record = try? JSONDecoder().decode(NapDecisionRecord.self, from: data) else { return }
        DispatchQueue.main.async {
            NapDecisionStore.shared.add(record)
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
