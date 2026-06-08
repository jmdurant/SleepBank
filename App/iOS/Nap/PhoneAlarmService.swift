//
//  PhoneAlarmService.swift
//  SleepBank
//
//  The wake alarm for a phone-hosted nap: an escalating beeping tone (synthesized,
//  no asset) plus haptics. Uses the .playback audio category so it sounds even
//  with the ringer switch on silent.
//

import Foundation
import AVFoundation
import UIKit

@Observable
class PhoneAlarmService {

    private(set) var isAlarming = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var node: AVAudioSourceNode?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startAt: Date?
    @ObservationIgnored private var sampleIndex: Float = 0
    @ObservationIgnored private let sampleRate: Float = 44_100

    func start() {
        guard !isAlarming else { return }
        isAlarming = true
        startAt = Date()
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
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        engine.connect(node, to: engine.mainMixerNode, format: format)
        self.node = node
    }
}
