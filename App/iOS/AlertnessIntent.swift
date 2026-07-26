//
//  AlertnessIntent.swift
//  SleepBank
//
//  Siri / Shortcuts / Action-button intent: "How alert am I?" Answers from the
//  App Group rhythm snapshot (same source as the widget), so it works without
//  opening the app, and folds in a nap suggestion when one would help.
//

import AppIntents
import Foundation
import SleepBankCore

struct AlertnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Check My Alertness"
    static var description = IntentDescription("Your predicted alertness right now, and whether a nap would help.")
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snap = RhythmSnapshot.load() else {
            return .result(dialog: "Open SleepBank once so it can read your sleep and set up your alertness rhythm.")
        }
        let now = Date()
        let rhythm = snap.rebuild()
        let level = rhythm.level(at: now)
        let phase = AlertnessRhythm.phaseLabel(at: now).lowercased()
        var message = "Your alert score is about \(pct(level)) — \(phase)."

        // Add a nap suggestion only if a nap now would meaningfully lift the day.
        let napEnd = now.addingTimeInterval(NapType.power.targetWakeAfterOnset)
        let projection = rhythm.projectedReadings(napType: .power, napAt: now,
                                                  from: napEnd, to: now.addingTimeInterval(5 * 3600))
        if let peak = projection.max(by: { $0.level < $1.level }),
           peak.level - rhythm.level(at: peak.date) >= 0.03 {
            message += " A power nap now could lift you to about \(pct(peak.level))%."
        } else if Calendar.current.component(.hour, from: now) < 11, rhythm.morningLightDose < 0.5 {
            message += " Some morning daylight would help anchor your day."
        }

        return .result(dialog: IntentDialog(stringLiteral: message))
    }

    private func pct(_ level: Double) -> Int { Int((level * 100).rounded()) }
}
