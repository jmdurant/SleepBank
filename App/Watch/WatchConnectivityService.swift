//
//  WatchConnectivityService.swift
//  SleepBank Watch App
//
//  Watch side of the link. Receives the phone's last-night sleep timeline via
//  application context and republishes it as SleepSamples for the chart.
//

import Foundation
import WatchConnectivity
import WidgetKit
import SleepChartKit
import SleepBankCore

@Observable
class WatchConnectivityService: NSObject, WCSessionDelegate {

    static let shared = WatchConnectivityService()

    var lastNightSamples: [SleepSample] = []

    /// Latest live H10 reading forwarded from the phone, with arrival time so the
    /// nap loop can ignore stale data and fall back to wrist HR.
    private var externalHR: Int?
    private var externalHRV: Double?
    private var externalHRAt: Date?
    var externalHeartRateAt: Date? { externalHRAt }
    private var externalHRVAt: Date?
    private var napID = UUID()
    private var napStartedAt = Date()
    private var napSequence = 0
    private var retryTimer: Timer?
    private var commandLedger = RelayCommandLedger(
        handled: UserDefaults.standard.stringArray(forKey: "relayCommands") ?? [],
        latestIssuedAt: UserDefaults.standard.dictionary(forKey: "relayCommandTimes") as? [String: TimeInterval] ?? [:]
    )
    private let outbox = RelayFileOutbox(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PendingNapDecisions"))

    func beginNap(at date: Date) {
        napID = UUID(); napStartedAt = date; napSequence = 0
    }
    private var eegConfidence: Double?
    private var eegDeep = false
    private var eegAt: Date?
    private let freshness: TimeInterval = 10

    /// Fresh external HR/HRV, or nil if none has arrived recently.
    var freshExternalHR: Int? { fresh(externalHRAt) ? externalHR : nil }
    var freshExternalHRV: Double? { fresh(externalHRVAt) ? externalHRV : nil }
    /// Fresh EEG onset signal forwarded from the phone's Muse pipeline.
    var freshEEGConfidence: Double? { fresh(eegAt) ? eegConfidence : nil }
    var freshEEGDeep: Bool { fresh(eegAt) ? eegDeep : false }

    private func fresh(_ at: Date?) -> Bool {
        RelayTimestamp.isFresh(at, within: freshness)
    }

    /// Forward a nap state event to the phone (sensors, sound, and the Live
    /// Activity all key off this). transferUserInfo is queued and wakes the
    /// phone even when backgrounded.
    /// - event: "start" | "update" | "onset" | "end"
    func sendNap(event: String, phase: String, wakeTarget: Date?, heartRate: Int, heartRateAt: Date? = nil,
                 typeTitle: String, onset: Bool, napsToday: Int = 0, minutesToday: Int = 0) {
        napSequence += 1
        var info: [String: Any] = [
            "napID": napID.uuidString, "napStartedAt": napStartedAt.timeIntervalSince1970,
            "sequence": napSequence, "eventAt": Date().timeIntervalSince1970,
            "napEvent": event, "phase": phase, "hr": heartRate,
            "type": typeTitle, "onset": onset,
            "napsToday": napsToday, "minutesToday": minutesToday,
        ]
        if let heartRateAt { info["heartRateAt"] = heartRateAt.timeIntervalSince1970 }
        if let wt = wakeTarget { info["wakeTarget"] = wt.timeIntervalSince1970 }
        var pending = UserDefaults.standard.array(forKey: "pendingNapEvents") as? [[String: Any]] ?? []
        pending.append(info)
        UserDefaults.standard.set(pending, forKey: "pendingNapEvents")
        flushNapEvents()
    }

    private func flushNapEvents() {
        guard WCSession.default.activationState == .activated else { return }
        let pending = UserDefaults.standard.array(forKey: "pendingNapEvents") as? [[String: Any]] ?? []
        for event in pending { WCSession.default.transferUserInfo(event) }
        UserDefaults.standard.removeObject(forKey: "pendingNapEvents")
    }

    /// Forward wrist HR + motion to the phone (for a phone nap using the Watch as a
    /// live sensor). Best-effort, only when reachable.
    func sendWatchSensors(bpm: Int, heartRateAt: Date?, motionAt: Date?, movement: Double, stillSeconds: Double) {
        let s = WCSession.default
        guard s.activationState == .activated, s.isReachable else { return }
        var payload: [String: Any] = ["watchHR": bpm, "watchMove": movement, "watchStill": stillSeconds]
        if let heartRateAt { payload["heartRateAt"] = heartRateAt.timeIntervalSince1970 }
        if let motionAt { payload["motionAt"] = motionAt.timeIntervalSince1970 }
        s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    /// Send a completed nap's decision + feature trace to the phone as a file
    /// (transferFile handles the larger payload and delivers in the background).
    func sendDecision(_ record: NapDecisionRecord) {
        do {
            try outbox.save(id: record.id, data: JSONEncoder().encode(record))
            flushDecisions()
        } catch { print("[WatchConnectivity] Could not retain nap trace: \(error)") }
    }

    func flushDecisions() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        for url in outbox.pending {
            let id = url.deletingPathExtension().lastPathComponent
            guard !session.outstandingFileTransfers.contains(where: { $0.file.metadata?["decisionID"] as? String == id }) else { continue }
            session.transferFile(url, metadata: ["kind": "napDecision", "decisionID": id])
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        // Keep the source until a durable receiver ACK. The timer/next activation
        // retries failed deliveries and successful deliveries whose ACK was lost.
        if let error { print("[WatchConnectivity] Trace delivery will retry: \(error)") }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        ConnectivityBackgroundDelivery.shared.perform { self.flushDecisions() }
    }

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.flushDecisions() }
    }

    private func decode(_ context: [String: Any]) {
        if let streak = context["morningLightStreak"] as? Int {
            SharedStore.morningLightStreak = streak
            WidgetCenter.shared.reloadAllTimelines()
        }
        if let snapshot = context["rhythmSnapshot"] as? Data {
            SharedStore.rhythmSnapshot = snapshot   // for the watch's Today's Plan
            Self.refreshPlanSummary()               // digest for the plan complication
        }
        // Mirror the phone's chosen wind-down guide so a watch-started nap paces it.
        if let raw = context["relaxGuide"] as? String,
           let guide = RelaxationGuide(rawValue: raw) {
            GuidedRelaxationService.shared.guide = guide
        }
        guard let data = context["lastNight"] as? Data,
              let dtos = try? JSONDecoder().decode([SleepSampleDTO].self, from: data) else { return }
        self.lastNightSamples = dtos.sleepSamples
    }

    /// Recompute the compact plan digest the complication reads, from the latest
    /// synced rhythm snapshot. Safe to call on launch and on each sync.
    static func refreshPlanSummary() {
        guard let snapshot = RhythmSnapshot.load(), let rhythm = snapshot.rebuild() else {
            SharedStore.planSummary = nil
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let plan = DayPlan.build(rhythm: rhythm, now: Date())
        let summary = PlanSummary(
            startPct: Int((plan.startingLevel * 100).rounded()),
            isShortNight: plan.isShortNight,
            items: plan.items.map { PlanSummary.Item(kind: $0.kind.rawValue, time: $0.time, done: $0.done) }
        )
        SharedStore.planSummary = try? JSONEncoder().encode(summary)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        ConnectivityBackgroundDelivery.shared.activationFinished(error: error)
        ConnectivityBackgroundDelivery.shared.perform {
            self.decode(session.receivedApplicationContext)
            self.flushNapEvents()
            self.flushDecisions()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ConnectivityBackgroundDelivery.shared.perform { self.decode(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        self.session(session, didReceiveMessage: userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        ConnectivityBackgroundDelivery.shared.perform {
            if let raw = message["decisionAck"] as? String, let id = UUID(uuidString: raw) {
                do { try self.outbox.acknowledge(id) }
                catch { print("[WatchConnectivity] Trace ACK cleanup failed: \(error)") }
                return
            }
            if message["commandID"] != nil {
                self.receiveCommand(message)
                return
            }
            let hrAt = RelayTimestamp.date(message["heartRateAt"])
            if let bpm = message["liveHR"] as? Int, bpm > 0,
               RelayTimestamp.accepts(hrAt, after: self.externalHRAt) {
                self.externalHR = bpm
                self.externalHRAt = hrAt
            }
            let hrvAt = RelayTimestamp.date(message["hrvAt"])
            if let hrv = message["liveHRV"] as? Double, hrv.isFinite, hrv > 0,
               RelayTimestamp.accepts(hrvAt, after: self.externalHRVAt) {
                self.externalHRV = hrv
                self.externalHRVAt = hrvAt
            }
            let eegAt = RelayTimestamp.date(message["eegAt"])
            if let conf = message["eegOnset"] as? Double, conf.isFinite, (0...1).contains(conf),
               RelayTimestamp.accepts(eegAt, after: self.eegAt) {
                self.eegConfidence = conf
                self.eegDeep = (message["eegDeep"] as? Bool) ?? false
                self.eegAt = eegAt
            }
        }
    }

    private func receiveCommand(_ message: [String: Any]) {
        let decision = commandLedger.receive(message)
        if decision == .accepted {
            // Persist before applying; a duplicate delivery cannot start a second workout.
            UserDefaults.standard.set(commandLedger.handled, forKey: "relayCommands")
            UserDefaults.standard.set(commandLedger.latestIssuedAt, forKey: "relayCommandTimes")
            if let kind = message["startWorkout"] as? String {
                ActivityWorkoutService.shared.start(kind: kind)
            } else if let on = message["watchHRMirror"] as? Bool {
                on ? WatchHRRelay.shared.start() : WatchHRRelay.shared.stop()
            }
        }
        if let id = message["commandID"] as? String {
            WCSession.default.transferUserInfo(["commandAck": id, "status": decision.rawValue])
        }
    }
}
