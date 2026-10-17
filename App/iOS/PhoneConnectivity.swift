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
    private var pendingSummary: [String: Any]?
    private var pendingCommands: [[String: Any]] = []
    private var lastCommandID: String?
    private(set) var lastCommandStatus: String?
    private var napState = NapRelayState.load()


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
        var context: [String: Any] = ["morningLightStreak": morningLightStreak]
        if let data = try? JSONEncoder().encode(samples.dtos) {
            context["lastNight"] = data
        }
        if let rhythmSnapshot { context["rhythmSnapshot"] = rhythmSnapshot }
        // Carry the chosen wind-down guide so a watch-started nap can pace it on the wrist.
        context["relaxGuide"] = GuidedRelaxationService.shared.guide.rawValue
        pendingSummary = context
        flushSummary()
    }

    /// Forward a live H10 reading to the watch's nap loop. Best-effort: only sent
    /// when the watch app is reachable (it is during a nap, kept alive by the
    /// workout session); otherwise the watch falls back to its own wrist HR.
    func sendLiveHR(bpm: Int, hrv: Double, heartRateAt: Date?, hrvAt: Date?) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable, bpm > 0 else { return }
        var payload: [String: Any] = ["liveHR": bpm, "liveHRV": hrv]
        if let heartRateAt { payload["heartRateAt"] = heartRateAt.timeIntervalSince1970 }
        if let hrvAt { payload["hrvAt"] = hrvAt.timeIntervalSince1970 }
        session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    /// State snapshots never share their channel with expiring commands.
    func startWorkout(_ kind: String) { sendCommand(["startWorkout": kind]) }
    func requestWatchHR(_ on: Bool) { sendCommand(["watchHRMirror": on]) }

    private func sendCommand(_ command: [String: Any]) {
        var payload = command
        let id = UUID().uuidString
        payload["commandID"] = id
        lastCommandID = id
        payload["issuedAt"] = Date().timeIntervalSince1970
        payload["expiresAt"] = Date().addingTimeInterval(30).timeIntervalSince1970
        lastCommandStatus = "Waiting for Watch"
        pendingCommands.append(payload)
        flushCommands()
    }

    private func flushCommands() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let pending = pendingCommands
        pendingCommands.removeAll()
        for payload in pending {
            guard let expires = RelayTimestamp.date(payload["expiresAt"]), expires > Date() else {
                if payload["commandID"] as? String == lastCommandID {
                    lastCommandStatus = "Request expired. Open SleepBank on Watch and try again."
                }
                continue
            }
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { _ in session.transferUserInfo(payload) }
            } else { session.transferUserInfo(payload) }
        }
    }

    private func flushSummary() {
        guard WCSession.default.activationState == .activated, let pendingSummary else { return }
        do {
            try WCSession.default.updateApplicationContext(pendingSummary)
            self.pendingSummary = nil
        } catch { print("[PhoneConnectivity] Summary delivery deferred: \(error)") }
    }

    /// Forward the Muse EEG onset signal to the watch nap loop.
    func sendEEG(onsetConfidence: Double, deepApproaching: Bool, sampledAt: Date?) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        guard let sampledAt else { return }
        session.sendMessage(["eegOnset": onsetConfidence, "eegDeep": deepApproaching, "eegAt": sampledAt.timeIntervalSince1970],
                            replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Session control from the watch

    /// The watch told us a nap started/ended. On start, connect and stream the
    /// paired sensors so their data feeds the nap loop; on end, stand down.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let status = userInfo["status"] as? String, let id = userInfo["commandAck"] as? String {
            DispatchQueue.main.async {
                guard id == self.lastCommandID else { return }
                self.lastCommandStatus = ["accepted", "duplicate"].contains(status)
                    ? "Watch received request" : "Request expired. Open SleepBank on Watch and try again."
            }
            return
        }
        guard let event = userInfo["napEvent"] as? String else { return }
        DispatchQueue.main.async {
            guard self.napState.receive(userInfo) else { return }
            self.napState.save()
            switch event {
            case "start":
                PolarH10Service.shared.autoConnect()
                MuseService.shared.startScanning()
                if NoiseService.shared.autoPlayDuringNap { NoiseService.shared.play() }
                LiveActivityManager.shared.start(
                    title: userInfo["type"] as? String ?? "Nap",
                    sessionStart: RelayTimestamp.date(userInfo["napStartedAt"]) ?? Date(),
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
            if NapDecisionStore.shared.add(record) {
                let today = NapDecisionStore.shared.records.filter { Calendar.current.isDateInToday($0.end) }
                SharedStore.napsToday = today.count
                SharedStore.minutesToday = today.reduce(0) { $0 + $1.asleepMinutes }
                WidgetCenter.shared.reloadAllTimelines()
                session.transferUserInfo(["decisionAck": record.id.uuidString])
            }
        }
    }

    private static func contentState(from info: [String: Any]) -> NapActivityAttributes.ContentState {
        let wake = (info["wakeTarget"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }
        return NapActivityAttributes.ContentState(
            phase: info["phase"] as? String ?? "settling",
            wakeTarget: wake,
            heartRate: info["hr"] as? Int ?? 0,
            onsetDetected: info["onset"] as? Bool ?? false,
            heartRateAt: RelayTimestamp.date(info["heartRateAt"])
        )
    }

    /// Live wrist HR + motion forwarded from the watch (for a phone nap).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["watchHR"] != nil || message["watchMove"] != nil else { return }
        let bpm = message["watchHR"] as? Int ?? 0
        let move = message["watchMove"] as? Double
        let still = message["watchStill"] as? Double
        DispatchQueue.main.async { WatchHRService.shared.update(bpm: bpm, heartRateAt: RelayTimestamp.date(message["heartRateAt"]),
                                                         movement: move, stillSeconds: still, motionAt: RelayTimestamp.date(message["motionAt"])) }
    }

    // MARK: - WCSessionDelegate (iOS requires all three lifecycle methods)

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.flushSummary(); self.flushCommands() }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for the next paired watch.
        WCSession.default.activate()
    }
}
