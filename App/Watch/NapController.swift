//
//  NapController.swift
//  SleepBank Watch App
//
//  The wrist-side conductor. Owns the sensor services, feeds their live signals
//  into the sensor-agnostic NapEngine each second, reflects the resulting phase
//  to the UI, and drives the SmartAlarmService when the engine says it's time to
//  wake. The detection/timing logic itself lives in SleepBankCore (tested,
//  device-free); this class is just the wiring to real hardware.
//

import Foundation
import SleepBankCore

@Observable
class NapController {

    let workout = NapWorkoutService()
    let motion = MotionService()
    let alarm = SmartAlarmService()
    let store = NapStore()
    private let sync = WatchConnectivityService.shared

    /// True when the loop is currently using H10 data forwarded from the phone
    /// rather than wrist HR.
    private(set) var usingExternalHR = false

    private(set) var napType: NapType = .power
    private(set) var phase: NapPhase = .finished
    private(set) var isNapping = false
    private(set) var onsetDetected = false
    private(set) var timeUntilWake: TimeInterval = 0
    /// The just-finished nap, shown as a recap until dismissed.
    private(set) var lastCompletedNap: NapRecord?

    private var engine: NapEngine?
    private var timer: Timer?
    private var wakeScheduled = false
    private var lastOnset: Date?
    private var lastWakeReason: WakeReason?
    private var lastSentPhase: NapPhase?
    private var liveTickCounter = 0

    var heartRate: Int { sync.freshExternalHR ?? workout.currentHeartRate }
    var movementIntensity: Double { motion.movementIntensity }
    var isAlarming: Bool { alarm.isAlarming }

    func requestPermissions() {
        workout.requestPermissions()
    }

    func start(type: NapType) {
        guard !isNapping else { return }
        napType = type

        let detector = HeartRateImmobilityOnsetDetector()
        let now = Date()
        engine = NapEngine(type: type, sessionStart: now, detector: detector)
        wakeScheduled = false
        onsetDetected = false
        lastOnset = nil
        lastWakeReason = nil

        do {
            try workout.start()
        } catch {
            print("[NapController] failed to start workout session: \(error)")
        }
        motion.startMonitoring()
        if NoiseService.shared.autoPlayDuringNap { NoiseService.shared.play() }
        // Tell the phone to connect sensors, start sound, and raise the Live Activity.
        sync.sendNap(event: "start", phase: NapPhase.settling.rawValue,
                     wakeTarget: engine?.ceiling, heartRate: 0,
                     typeTitle: type.title, onset: false)
        lastSentPhase = .settling
        liveTickCounter = 0
        isNapping = true
        phase = .settling

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let engine else { return }

        // Prefer the H10 (chest strap, more reliable + gives HRV) when the phone
        // is forwarding fresh data; otherwise use wrist HR. HRV is only present
        // with the H10, so onset HRV-fusion engages automatically when available.
        let wristHR = workout.currentHeartRate > 0 ? workout.currentHeartRate : nil
        let externalHR = sync.freshExternalHR
        usingExternalHR = externalHR != nil
        let signal = OnsetSignal(
            heartRate: externalHR ?? wristHR,
            movementIntensity: motion.movementIntensity,
            stillSeconds: motion.stillSeconds,
            hrvRMSSD: sync.freshExternalHRV,
            eegOnsetConfidence: sync.freshEEGConfidence,
            eegDeepApproaching: sync.freshEEGDeep
        )
        let result = engine.tick(now: Date(), signal: signal)

        phase = result.phase
        timeUntilWake = result.timeUntilWake ?? 0
        let wasOnset = onsetDetected
        onsetDetected = result.onsetTime != nil
        lastOnset = result.onsetTime
        if let reason = result.wakeReason { lastWakeReason = reason }

        let effectiveTarget = result.wakeTarget ?? engine.ceiling
        liveTickCounter += 1

        // First moment of onset: fade the relaxing sound (here and on the phone)
        // and push the new wake target to the Live Activity.
        if onsetDetected && !wasOnset {
            NoiseService.shared.fadeOut()
            sync.sendNap(event: "onset", phase: result.phase.rawValue, wakeTarget: effectiveTarget,
                         heartRate: heartRate, typeTitle: napType.title, onset: true)
            lastSentPhase = result.phase
        } else if result.phase != lastSentPhase || liveTickCounter % 30 == 0 {
            // Phase change, or a periodic refresh so HR doesn't go stale.
            sync.sendNap(event: "update", phase: result.phase.rawValue, wakeTarget: effectiveTarget,
                         heartRate: heartRate, typeTitle: napType.title, onset: onsetDetected)
            lastSentPhase = result.phase
        }

        // Schedule the guaranteed-wake session as soon as onset gives us a target.
        if !wakeScheduled, let target = result.wakeTarget {
            alarm.scheduleWake(at: target)
            wakeScheduled = true
        }
        // Sound the alarm once the engine says so (idempotent).
        if result.isAlarming {
            alarm.startAlarm()
        }
    }

    /// Ends the session — used both for a manual stop and for the user clearing
    /// the alarm after a successful wake.
    func stop() {
        // Record the nap as a deposit before tearing down.
        if let engine {
            let record = NapRecord(
                start: engine.sessionStart,
                end: Date(),
                type: napType,
                onset: lastOnset,
                wakeReason: lastWakeReason ?? .manual
            )
            store.add(record)
            lastCompletedNap = record
        }

        engine?.finish()
        alarm.stop()
        workout.stop()
        motion.stopMonitoring()
        NoiseService.shared.fadeOut()    // stop watch sound if onset never fired
        // Tell the phone to stand sensors down and end the Live Activity.
        sync.sendNap(event: "end", phase: NapPhase.finished.rawValue, wakeTarget: nil,
                     heartRate: heartRate, typeTitle: napType.title, onset: onsetDetected)
        timer?.invalidate()
        timer = nil
        isNapping = false
        phase = .finished
        timeUntilWake = 0
        onsetDetected = false
        wakeScheduled = false
        engine = nil
    }

    func dismissRecap() {
        lastCompletedNap = nil
    }

    // MARK: - Display helpers

    var phaseLabel: String {
        switch phase {
        case .settling:   return "Settling…"
        case .monitoring: return "Watching for sleep"
        case .asleep:     return "Asleep · wake armed"
        case .waking:     return "Time to wake"
        case .finished:   return ""
        }
    }

    var countdownLabel: String {
        let secs = max(0, Int(timeUntilWake))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
