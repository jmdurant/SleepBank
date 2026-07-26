//
//  PhoneAlarmService.swift
//  SleepBank
//
//  The wake alarm for a phone-hosted nap. AlarmKit owns the dependable system
//  wake (Lock Screen / Dynamic Island / StandBy, even when SleepBank isn't
//  visible). The synthesized tone and haptics remain as a fallback when AlarmKit
//  permission is unavailable.
//

import Foundation
import AlarmKit
import AppIntents
import AVFoundation
import SwiftUI
import UIKit
import os

private let alarmLog = Logger(subsystem: "com.doctordurant.sleepbank", category: "PhoneAlarm")

private struct SleepBankAlarmMetadata: AlarmMetadata {
    let napTitle: String
}

private struct StopSleepBankAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop SleepBank Alarm"
    static var isDiscoverable: Bool = false
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult {
        await MainActor.run { PhoneNapController.shared.stop() }
        return .result()
    }
}

@Observable
class PhoneAlarmService {

    private(set) var isAlarming = false
    private(set) var systemAlarmArmed = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var node: AVAudioSourceNode?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startAt: Date?
    @ObservationIgnored private var systemAlarmID: UUID?
    @ObservationIgnored private var scheduleGeneration: UInt = 0
    @ObservationIgnored private var sampleIndex: Float = 0
    @ObservationIgnored private let sampleRate: Float = 44_100

    /// Schedule the onset-relative target as a real system alarm. If permission
    /// is denied or scheduling fails, `start()` retains the in-app fallback.
    func scheduleWake(at date: Date, napTitle: String) async {
        guard date > Date() else { return }

        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        cancelSystemAlarm()

        let manager = AlarmManager.shared
        var authorization = manager.authorizationState
        if authorization == .notDetermined {
            do {
                authorization = try await manager.requestAuthorization()
            } catch {
                alarmLog.error("Alarm authorization failed: \(error.localizedDescription)")
                return
            }
        }
        guard authorization == .authorized else {
            alarmLog.notice("System wake unavailable; using in-app alarm fallback")
            return
        }

        let id = UUID()
        let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(title: "SleepBank — time to wake")
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: SleepBankAlarmMetadata(napTitle: napTitle),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: StopSleepBankAlarmIntent()
        )

        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
            // The nap may have ended while authorization/scheduling was awaiting.
            guard generation == scheduleGeneration else {
                try? manager.cancel(id: id)
                return
            }
            systemAlarmID = id
            systemAlarmArmed = true
            alarmLog.info("Scheduled system wake at \(date)")
        } catch {
            alarmLog.error("System wake scheduling failed: \(error.localizedDescription)")
        }
    }

    func start() {
        guard !isAlarming else { return }
        isAlarming = true
        startAt = Date()

        // AlarmKit is already presenting and sounding the system alarm. Running
        // a second audio engine over it would produce a doubled alarm.
        guard !systemAlarmArmed else { return }

        configureSession()
        if node == nil { installNode() }
        engine.mainMixerNode.outputVolume = 0.5
        try? engine.start()
        pulse()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.pulse() }
    }

    func stop() {
        isAlarming = false
        timer?.invalidate(); timer = nil
        startAt = nil
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        scheduleGeneration &+= 1
        cancelSystemAlarm()
    }

    private func cancelSystemAlarm() {
        guard let id = systemAlarmID else {
            systemAlarmArmed = false
            return
        }
        // stop silences an alert in progress; cancel removes the fixed alarm.
        try? AlarmManager.shared.stop(id: id)
        try? AlarmManager.shared.cancel(id: id)
        systemAlarmID = nil
        systemAlarmArmed = false
    }

    /// Haptic on each beat; volume ramps the longer it goes unanswered.
    private func pulse() {
        let elapsed = startAt.map { Date().timeIntervalSince($0) } ?? 0
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        engine.mainMixerNode.outputVolume = min(1.0, 0.5 + Float(elapsed) / 30)
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
    }

    /// Amplitude-modulated 880 Hz tone → ~4 beeps/sec.
    private func installNode() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sr = Float(format.sampleRate > 0 ? format.sampleRate : Double(sampleRate))
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let t = self.sampleIndex / sr
                let beat = t.truncatingRemainder(dividingBy: 0.25)
                let envelope: Float = beat < 0.15 ? 1 : 0           // 0.15s on, 0.10s off
                let value = sin(2 * .pi * 880 * t) * envelope * 0.5
                for buffer in abl {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = value
                }
                self.sampleIndex += 1
            }
            return noErr
        }
        engine.attach(node)
        do {
            try engine.connectNode(node, to: engine.mainMixerNode, format: format)
        } catch {
            engine.detach(node)
            alarmLog.error("Fallback audio graph connection failed: \(error.localizedDescription)")
            return
        }
        self.node = node
    }
}
