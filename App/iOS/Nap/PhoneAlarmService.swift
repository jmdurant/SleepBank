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

@MainActor
protocol SystemWakeAlarm {
    func authorize() async throws -> Bool
    func schedule(id: UUID, at: Date, napTitle: String) async throws
    func isAlerting(id: UUID) -> Bool
    func cancel(id: UUID)
}

@MainActor
private struct AlarmKitWakeAlarm: SystemWakeAlarm {
    func authorize() async throws -> Bool {
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined {
            return try await manager.requestAuthorization() == .authorized
        }
        return manager.authorizationState == .authorized
    }
    func schedule(id: UUID, at date: Date, napTitle: String) async throws {
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: AlarmPresentation.Alert(title: "SleepBank — time to wake")),
            metadata: SleepBankAlarmMetadata(napTitle: napTitle), tintColor: .orange)
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date), attributes: attributes, stopIntent: StopSleepBankAlarmIntent())
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }
    func isAlerting(id: UUID) -> Bool {
        (try? AlarmManager.shared.alarms.contains { $0.id == id && $0.state == .alerting }) ?? false
    }
    func cancel(id: UUID) {
        try? AlarmManager.shared.stop(id: id)
        try? AlarmManager.shared.cancel(id: id)
    }
}

protocol PhoneWakeOutput {
    func pulse(elapsed: TimeInterval)
    func pause()
    func stop()
}

@MainActor
@Observable
final class PhoneAlarmService {
    private(set) var isAlarming = false
    private(set) var systemAlarmArmed = false
    @ObservationIgnored private let system: SystemWakeAlarm
    @ObservationIgnored private let output: PhoneWakeOutput
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var earlyWakeTask: Task<Void, Never>?
    private var startAt: Date?
    private var systemAlarmID: UUID?
    private var scheduleGeneration: UInt = 0

    init(system: SystemWakeAlarm? = nil, output: PhoneWakeOutput? = nil) {
        self.system = system ?? AlarmKitWakeAlarm()
        self.output = output ?? SynthesizedWakeOutput()
    }

    func scheduleWake(at date: Date, napTitle: String) async {
        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        do {
            guard try await system.authorize(), generation == scheduleGeneration, !Task.isCancelled else { return }
            let id = UUID()
            try await system.schedule(id: id, at: max(date, Date().addingTimeInterval(0.5)), napTitle: napTitle)
            guard generation == scheduleGeneration, !Task.isCancelled else {
                system.cancel(id: id)
                return
            }
            // Retain the old safety alarm until its replacement actually exists.
            let previous = systemAlarmID
            systemAlarmID = id
            systemAlarmArmed = true
            if let previous { system.cancel(id: previous) }
        } catch {
            alarmLog.error("System wake scheduling failed: \(error.localizedDescription)")
        }
    }

    func start() {
        guard !isAlarming else { return }
        isAlarming = true
        startAt = Date()
        // Only an actually alerting system alarm may silence the fallback.
        pulse()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pulse() }
        }
        if !systemAlarmIsAlerting {
            earlyWakeTask = Task { [weak self] in
                guard let self, self.isAlarming, !Task.isCancelled else { return }
                await self.scheduleWake(at: Date().addingTimeInterval(1), napTitle: "Nap")
            }
        }
    }

    func stop() {
        isAlarming = false
        timer?.invalidate(); timer = nil
        earlyWakeTask?.cancel(); earlyWakeTask = nil
        startAt = nil
        output.stop()
        scheduleGeneration &+= 1
        if let id = systemAlarmID { system.cancel(id: id) }
        systemAlarmID = nil
        systemAlarmArmed = false
    }

    private var systemAlarmIsAlerting: Bool {
        systemAlarmID.map { system.isAlerting(id: $0) } ?? false
    }

    private func pulse() {
        guard isAlarming else { return }
        if systemAlarmIsAlerting { output.pause() }
        else { output.pulse(elapsed: startAt.map { Date().timeIntervalSince($0) } ?? 0) }
    }
}

private final class SynthesizedWakeOutput: PhoneWakeOutput {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var sampleIndex: Float = 0
    private let sampleRate: Float = 44_100

    func pulse(elapsed: TimeInterval) {
        if !engine.isRunning {
            configureSession()
            if node == nil { installNode() }
            do { try engine.start() }
            catch { alarmLog.error("Fallback audio failed: \(error.localizedDescription)") }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        engine.mainMixerNode.outputVolume = min(1, 0.5 + Float(elapsed) / 30)
    }
    func pause() { engine.pause() }
    func stop() {
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
