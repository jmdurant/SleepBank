//
//  GuidedRelaxationService.swift
//  SleepBank (shared — phone and watch)
//
//  A spoken wind-down for the settling phase, via the system speech synthesizer
//  (no recordings). Two evidence-aligned techniques:
//   • Paced breathing (4-7-8) — a long exhale activates the parasympathetic
//     system and lowers arousal.
//   • Eye + body relaxation — let the eyes settle and drift upward, then release
//     tension downward through the body.
//  Plays over the relaxing sound and stops once you're asleep.
//

import Foundation
import AVFoundation

enum RelaxationGuide: String, CaseIterable, Identifiable, Hashable {
    case none
    case breathing478
    case eyeRelaxation

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Off"
        case .breathing478: return "Paced breathing (4-7-8)"
        case .eyeRelaxation: return "Eye & body relaxation"
        }
    }
}

@Observable
class GuidedRelaxationService: NSObject, AVSpeechSynthesizerDelegate {

    static let shared = GuidedRelaxationService()

    private(set) var isSpeaking = false

    /// Selected guide (stored so @Observable tracks it; persisted via didSet).
    var guide: RelaxationGuide = RelaxationGuide(rawValue: UserDefaults.standard.string(forKey: "relaxGuide") ?? "") ?? .none {
        didSet { UserDefaults.standard.set(guide.rawValue, forKey: "relaxGuide") }
    }
    var autoPlayDuringNap: Bool = UserDefaults.standard.bool(forKey: "relaxAutoPlay") {
        didSet { UserDefaults.standard.set(autoPlayDuringNap, forKey: "relaxAutoPlay") }
    }

    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private var active = false
    @ObservationIgnored private var current: RelaxationGuide = .none
    @ObservationIgnored private var cycle = 0

    override init() {
        super.init()
        synth.delegate = self
    }

    func start(_ guide: RelaxationGuide) {
        guard guide != .none else { return }
        configureSession()
        active = true
        current = guide
        cycle = 0
        isSpeaking = true
        NoiseService.shared.setDucked(true)   // drop the noise under the voice
        enqueueNextCycle()
    }

    func stop() {
        active = false
        isSpeaking = false
        synth.stopSpeaking(at: .immediate)
        NoiseService.shared.setDucked(false)
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
    }

    private func enqueueNextCycle() {
        guard active else { return }
        let utterances = script(for: current, cycle: cycle)
        cycle += 1
        guard !utterances.isEmpty else { stop(); return }   // script finished
        utterances.forEach { synth.speak($0) }
    }

    // MARK: - Scripts

    private func script(for guide: RelaxationGuide, cycle: Int) -> [AVSpeechUtterance] {
        switch guide {
        case .none:
            return []
        case .breathing478:
            if cycle == 0 {
                return [line("Let's slow your breathing. Follow my voice.", pause: 1.5)] + breathCycle()
            } else if cycle < 10 {
                return breathCycle()
            } else {
                return [line("Keep breathing slowly. Let yourself drift.", pause: 1)]  // last, then ends
            }
        case .eyeRelaxation:
            guard cycle == 0 else { return [] }   // one pass
            return [
                line("Let your eyes close.", pause: 2),
                line("Soften the small muscles around them.", pause: 3),
                line("Let your gaze drift, without focusing on anything.", pause: 3),
                line("Let your eyes settle, gently upward, toward a soft, distant point.", pause: 4),
                line("Feel them grow heavy, and still.", pause: 4),
                line("Let that heaviness spread to your jaw, your shoulders, your chest.", pause: 5),
                line("With each breath out, sink a little deeper.", pause: 6),
                line("There's nothing to do now. Just rest.", pause: 6),
            ]
        }
    }

    private func breathCycle() -> [AVSpeechUtterance] {
        [
            line("Breathe in", pause: 3.2),
            line("Hold", pause: 6.2),
            line("And breathe out, slowly", pause: 7.0),
        ]
    }

    private func line(_ text: String, pause: TimeInterval) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.5
        u.pitchMultiplier = 0.95
        u.volume = 0.9
        u.postUtteranceDelay = pause
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        return u
    }

    // MARK: - Delegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // When the queued cycle drains, enqueue the next one.
        if active, !synthesizer.isSpeaking {
            DispatchQueue.main.async { [weak self] in self?.enqueueNextCycle() }
        }
    }
}
