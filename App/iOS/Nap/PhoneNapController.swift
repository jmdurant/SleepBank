//
//  PhoneNapController.swift
//  SleepBank
//
//  Runs the full nap loop on the phone — the at-home mode that uses the paired
//  Polar H10 (HR + HRV) and Muse (EEG), plus the phone's own motion, to detect
//  onset, then sounds a phone alarm at the smart wake. Mirrors the watch's
//  NapController but hosted on iOS. The detection/timing logic is the shared,
//  tested SleepBankCore engine.
//

import Foundation
import WidgetKit
import SleepBankCore

@Observable
class PhoneNapController {

    static let shared = PhoneNapController()

    let alarm = PhoneAlarmService()
    private let motion = MotionService()
    private let polar = PolarH10Service.shared
    private let muse = MuseService.shared
    private let store = NapDecisionStore.shared
    private let recorder = NapSessionRecorder()
    /// Live HR from a phone workout session (e.g. AirPods Pro) — the fallback when
    /// no chest strap is connected. iOS 26+. Shared with the Sensors screen.
    let workoutHR = PhoneWorkoutHRService.shared

    private(set) var napType: NapType = .power
    private(set) var phase: NapPhase = .finished
    private(set) var isNapping = false
    private(set) var onsetDetected = false
    private(set) var timeUntilWake: TimeInterval = 0
    private(set) var lastCompletedNap: NapRecord?

    private var engine: NapEngine?
    private var detector: HeartRateImmobilityOnsetDetector?
    private var timer: Timer?
    private var lastOnset: Date?
    private var lastReason: WakeReason?
    private var wakeTarget: Date?
    private var tickCount = 0
    private(set) var spo2: Double = 0   // % — spot from HealthKit, completeness only

    var heartRate: Int { polar.currentHeartRate > 0 ? polar.currentHeartRate : (workoutHR.freshHeartRate ?? 0) }
    /// Which sensor is driving the live heart rate right now (for the nap readout).
    var heartRateSource: String? {
        if polar.currentHeartRate > 0 { return "H10" }
        if workoutHR.freshHeartRate != nil { return "AirPods" }
        return nil
    }
    var hrv: Double { polar.hrvRMSSD }
    var breathingRate: Double { polar.breathingRate }
    var museGood: Bool { muse.eeg.hasGoodSignal }
    var isAlarming: Bool { alarm.isAlarming }

    func start(type: NapType) {
        guard !isNapping else { return }
        napType = type

        // Make sure the at-home sensors are coming up.
        if !polar.isConnected { polar.autoConnect() }
        if !muse.isConnected { muse.startScanning() }

        let detector = HeartRateImmobilityOnsetDetector()
        self.detector = detector
        let now = Date()
        engine = NapEngine(type: type, sessionStart: now, detector: detector)
        recorder.begin(at: now)
        motion.startMonitoring()
        // Keep the app alive in the background for the whole nap (the iOS equivalent of
        // the watch's workout session) — via the audio session, even if sound is off.
        NoiseService.shared.beginKeepAlive()
        // Also open a workout session for live HR from AirPods Pro (and to keep sensors
        // hot) — the fallback when no chest strap is connected. iOS 26+.
        workoutHR.start()
        if NoiseService.shared.autoPlayDuringNap { NoiseService.shared.play() }
        // The phone's nap UI shows the visual breathing guide (which drives the haptic
        // pacer itself), so here we only auto-start the spoken body-scan if selected.
        if GuidedRelaxationService.shared.guide == .eyeRelaxation {
            GuidedRelaxationService.shared.start(.eyeRelaxation)
        }
        RawEEGRecorder.shared.begin()   // capture raw EEG for the YASA pipeline

        lastOnset = nil; lastReason = nil; wakeTarget = nil
        onsetDetected = false
        isNapping = true
        phase = .settling

        LiveActivityManager.shared.start(
            title: type.title, sessionStart: now,
            state: .init(phase: NapPhase.settling.rawValue, wakeTarget: engine?.ceiling,
                         heartRate: 0, onsetDetected: false)
        )
        SharedStore.napActive = true
        WidgetCenter.shared.reloadAllTimelines()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard let engine else { return }
        let now = Date()
        // Refresh the spot SpO2 occasionally (it's not a live stream).
        tickCount += 1
        if tickCount % 30 == 1 {
            Task { [weak self] in
                let value = await HealthKitService.shared.latestOxygenSaturation()
                await MainActor.run { self?.spo2 = value }
            }
        }
        // Prefer the H10 chest accelerometer for immobility (the phone may be on a
        // nightstand and never move); fall back to the phone's own motion.
        let usingChest = polar.isAccStreaming
        let movement = usingChest ? polar.movementIntensity : motion.movementIntensity
        let still = usingChest ? polar.stillSeconds : motion.stillSeconds
        let signal = OnsetSignal(
            heartRate: polar.currentHeartRate > 0 ? polar.currentHeartRate : workoutHR.freshHeartRate,
            movementIntensity: movement,
            stillSeconds: still,
            hrvRMSSD: polar.hrvRMSSD > 0 ? polar.hrvRMSSD : nil,
            eegOnsetConfidence: muse.eeg.hasGoodSignal ? Double(muse.eeg.onsetIndex) : nil,
            eegDeepApproaching: muse.eeg.hasGoodSignal && muse.eeg.deepSleepApproaching,
            breathing: (usingChest && polar.breathingRate > 0) ? polar.breathingRate : nil,
            spo2: spo2 > 0 ? spo2 : nil
        )
        let result = engine.tick(now: now, signal: signal)
        recorder.record(now: now, signal: signal, phase: result.phase)

        // Woke on their own before the alarm — end gracefully, no alarm.
        if result.naturallyWoke {
            lastOnset = result.onsetTime
            lastReason = .spontaneous
            stop()
            return
        }

        phase = result.phase
        timeUntilWake = result.timeUntilWake ?? 0
        let wasOnset = onsetDetected
        onsetDetected = result.onsetTime != nil
        lastOnset = result.onsetTime
        wakeTarget = result.wakeTarget
        if let reason = result.wakeReason { lastReason = reason }

        if onsetDetected && !wasOnset {
            NoiseService.shared.fadeOut()
            GuidedRelaxationService.shared.stop()   // asleep — the wind-down is done
        }
        if result.isAlarming { alarm.start() }

        LiveActivityManager.shared.update(.init(
            phase: result.phase.rawValue,
            wakeTarget: result.wakeTarget ?? engine.ceiling,
            heartRate: polar.currentHeartRate,
            onsetDetected: onsetDetected
        ))
    }

    func stop() {
        if let engine {
            let record = NapRecord(start: engine.sessionStart, end: Date(), type: napType,
                                   onset: lastOnset, wakeReason: lastReason ?? .manual)
            lastCompletedNap = record
            let decision = recorder.build(record: record, trigger: detector?.onsetTrigger)
            NapHealthWriter.shared.write(record)
            store.add(decision)
            // Export the nap's features + raw EEG under one shared stamp so the Mac
            // merge script can join them by time into a labeled training row set.
            let stamp = NapFiles.stamp(for: record.start)
            NapFiles.writeFeatures(decision, stamp: stamp)
            RawEEGRecorder.shared.finish(stamp: stamp)
            SharedStore.napsToday += record.onset != nil ? 1 : 0
            if let onset = record.onset {
                SharedStore.minutesToday += Int(max(0, record.end.timeIntervalSince(onset)) / 60)
            }
            engine.finish()
        }
        teardown()
    }

    /// Abandon the nap without recording it — no Health write, no recap, no count.
    /// For when a nap was started by mistake or interrupted.
    func cancel() {
        engine?.finish()
        RawEEGRecorder.shared.discard()   // drop the EEG buffer, don't write a file
        teardown()
    }

    /// Tear down sensors, audio, keep-alive, the workout session, and the live
    /// activity, and reset state. Shared by stop() and cancel().
    private func teardown() {
        alarm.stop()
        motion.stopMonitoring()
        NoiseService.shared.fadeOut()
        NoiseService.shared.endKeepAlive()   // release the background keep-alive
        workoutHR.stop()
        GuidedRelaxationService.shared.stop()
        LiveActivityManager.shared.end()
        SharedStore.napActive = false
        WidgetCenter.shared.reloadAllTimelines()
        timer?.invalidate(); timer = nil
        isNapping = false
        phase = .finished
        timeUntilWake = 0
        onsetDetected = false
        engine = nil
    }

    func dismissRecap() { lastCompletedNap = nil }

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
        let s = max(0, Int(timeUntilWake))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
