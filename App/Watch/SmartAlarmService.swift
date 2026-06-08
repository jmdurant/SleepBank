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

    /// Schedule the guaranteed-wake extended runtime session at `date`. Called
    /// once onset is detected and the wake target is known.
    func scheduleWake(at date: Date) {
        // Re-scheduling: tear down any prior session first.
        session?.invalidate()
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: date)
        session = s
        log.info("Scheduled smart-alarm wake at \(date)")
    }

    /// Begin (or continue) sounding the alarm now. Idempotent.
    func startAlarm() {
        guard !isAlarming else { return }
        isAlarming = true
        alarmStart = Date()
        configureAudioSession()
        fireTier()
        escalationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.fireTier()
        }
        log.info("Alarm started")
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
        // The scheduled wake time arrived — start sounding immediately.
        DispatchQueue.main.async { self.startAlarm() }
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        log.notice("Extended runtime session will expire")
    }

    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                error: Error?) {
        log.info("Extended runtime session invalidated: reason=\(reason.rawValue), error=\(error?.localizedDescription ?? "none")")
    }
}
