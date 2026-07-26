//
//  SmartAlarmService.swift
//  SleepBank Watch App
//
//  The wake half of the nap loop. Two cooperating mechanisms:
//
//  1. A WKExtendedRuntimeSession scheduled at the onset-relative wake target —
//     watchOS's purpose-built path for waking a user, allowed to run and play
//     haptics at the scheduled time even if everything else is suspended.
//  2. A foreground escalation loop (we're also kept alive by the nap's
//     HKWorkoutSession) that ramps the alert: gentle haptics → firmer haptics →
//     strongest haptics + audio, until the user clears it.
//
//  Haptic tiers are intentionally gentle first: the goal is to surface someone
//  out of light sleep, not to jolt them.
//

import Foundation
import WatchKit
import AVFoundation
import os

private let log = Logger(subsystem: "com.doctordurant.sleepbank.watchapp", category: "SmartAlarm")

@Observable
class SmartAlarmService: NSObject, WKExtendedRuntimeSessionDelegate {

    var isAlarming = false

    private var session: WKExtendedRuntimeSession?
    private var escalationTimer: Timer?
    private var alarmStart: Date?
    private var audioPlayer: AVAudioPlayer?
    private var systemAlertActive = false

    /// Schedule the guaranteed-wake extended runtime session at `date` while the
    /// watch app is active. SleepBank uses the absolute session ceiling here;
    /// the live workout loop remains free to wake earlier when appropriate.
    func scheduleWake(at date: Date) {
        // Re-scheduling: tear down any prior session first.
        session?.invalidate()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: date)
        session = s
        log.info("Scheduled smart-alarm wake at \(date)")
    }

    /// Reconnect a scheduled/running smart-alarm session handed back to us when
    /// watchOS relaunches the app in the background. The delegate must be assigned
    /// synchronously from WKApplicationDelegate or watchOS ends the session.
    func adopt(_ recoveredSession: WKExtendedRuntimeSession) {
        session = recoveredSession
        recoveredSession.delegate = self
        if recoveredSession.state == .running {
            beginSystemAlert(using: recoveredSession)
            startAlarm()
        }
        log.info("Recovered smart-alarm session in state \(recoveredSession.state.rawValue)")
    }

    /// Begin (or continue) sounding the alarm now. Idempotent.
    func startAlarm() {
        guard !isAlarming else { return }
        isAlarming = true
        alarmStart = Date()
        configureAudioSession()
        if !systemAlertActive { fireTier() }
        escalationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.advanceAlarm()
        }
        log.info("Alarm started")
    }

    private func advanceAlarm() {
        let elapsed = alarmStart.map { Date().timeIntervalSince($0) } ?? 0
        if systemAlertActive {
            // The OS owns the repeating haptics and alert UI. Add bundled audio
            // only at the final tier instead of playing duplicate haptics.
            if elapsed >= 25 { playAudioFallback() }
        } else {
            fireTier()
        }
    }

    /// Play the appropriate alert tier based on how long the alarm has been
    /// unanswered.
    private func fireTier() {
        let elapsed = alarmStart.map { Date().timeIntervalSince($0) } ?? 0
        let device = WKInterfaceDevice.current()
        switch elapsed {
        case ..<10:        // Tier 1 — gentle nudge
            device.play(.click)
        case 10..<25:      // Tier 2 — firmer
            device.play(.notification)
        default:           // Tier 3 — strongest + audio
            device.play(.failure)
            playAudioFallback()
        }
    }

    /// Stop everything and release the wake session.
    func stop() {
        isAlarming = false
        systemAlertActive = false
        escalationTimer?.invalidate()
        escalationTimer = nil
        alarmStart = nil
        audioPlayer?.stop()
        audioPlayer = nil
        session?.invalidate()
        session = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        log.info("Alarm stopped")
    }

    // MARK: - Audio

    private func configureAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? audio.setActive(true)
    }

    private func playAudioFallback() {
        guard audioPlayer == nil else { return }   // already playing
        // Looks for a bundled "alarm" sound. Until an asset ships, this is a
        // no-op and we lean on the strongest haptic tier.
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "caf")
            ?? Bundle.main.url(forResource: "alarm", withExtension: "mp3") else {
            log.notice("No bundled alarm audio asset — relying on haptics only")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.play()
            audioPlayer = player
        } catch {
            log.error("Audio fallback failed: \(error.localizedDescription)")
        }
    }

    // MARK: - WKExtendedRuntimeSessionDelegate

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // Use watchOS's repeating alarm path. If the app isn't visible, this also
        // presents the system Stop/Open alarm UI.
        DispatchQueue.main.async {
            self.beginSystemAlert(using: extendedRuntimeSession)
            self.startAlarm()
        }
    }

    private func beginSystemAlert(using extendedRuntimeSession: WKExtendedRuntimeSession) {
        guard extendedRuntimeSession.state == .running, !systemAlertActive else { return }
        systemAlertActive = true
        let started = Date()
        extendedRuntimeSession.notifyUser(hapticType: .click) { outHaptic in
            let elapsed = Date().timeIntervalSince(started)
            switch elapsed {
            case ..<10:
                outHaptic.pointee = .click
                return 4
            case 10..<25:
                outHaptic.pointee = .notification
                return 3
            default:
                outHaptic.pointee = .failure
                return 2
            }
        }
        log.info("System smart-alarm alert started")
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        log.notice("Extended runtime session will expire")
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        let userClearedAlarm = isAlarming
        systemAlertActive = false
        log.info("Extended runtime session invalidated: reason=\(reason.rawValue), error=\(error?.localizedDescription ?? "none")")
        if userClearedAlarm {
            // A Stop tap in the system alarm UI invalidates the session. Complete
            // the nap too, otherwise the engine would immediately start fallback
            // haptics again on its next tick.
            DispatchQueue.main.async { NapController.shared.stop() }
        }
    }
}
