//
//  EpworthStore.swift
//  SleepBank
//
//  The Epworth Sleepiness Scale (ESS) — 8 everyday situations, each rated 0–3 for
//  the chance of dozing, summed to 0–24. It measures *daytime sleepiness*, which is
//  the exact thing this app is built around, so it's the most on-thesis self-report
//  instrument we have. We administer it ourselves (HealthKit has no native sleep
//  questionnaire type — only PHQ-9/GAD-7) and keep results in-app for the user to
//  track over time. See docs/FDA_PATH.md for how this fits the regulatory plan.
//
//  Framing is deliberately non-diagnostic (a self-tracking score, not a screen for
//  a disorder) to stay inside the general-wellness exemption — see the band labels.
//
//  NOTE (commercial/clearance path): the ESS is © Murray Johns; commercial use
//  requires a license (MAPI Research Trust / eProvide). Fine for this prototype;
//  secure a license before any paid release or regulatory submission.
//

import Foundation

/// One completed Epworth scale, kept for trend-tracking.
struct EpworthResult: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let answers: [Int]   // 8 values, each 0–3
    var score: Int { answers.reduce(0, +) }   // 0–24

    init(id: UUID = UUID(), date: Date, answers: [Int]) {
        self.id = id
        self.date = date
        self.answers = answers
    }
}

@Observable
final class EpworthStore {
    static let shared = EpworthStore()

    /// The 8 ESS situations, in order.
    static let situations = [
        "Sitting and reading",
        "Watching TV",
        "Sitting inactive in a public place (a theater or a meeting)",
        "As a passenger in a car for an hour without a break",
        "Lying down to rest in the afternoon when circumstances permit",
        "Sitting and talking to someone",
        "Sitting quietly after lunch without alcohol",
        "In a car, while stopped a few minutes in traffic",
    ]

    /// The 0–3 response legend.
    static let choices = [
        (0, "Would never doze"),
        (1, "Slight chance"),
        (2, "Moderate chance"),
        (3, "High chance"),
    ]

    private(set) var results: [EpworthResult] = [] {
        didSet { save() }
    }

    private let key = "epworthResults"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([EpworthResult].self, from: data) {
            results = decoded.sorted { $0.date > $1.date }
        }
    }

    /// Most recent completed scale, if any.
    var latest: EpworthResult? { results.first }

    func record(answers: [Int]) {
        let result = EpworthResult(date: Date(), answers: answers)
        results.insert(result, at: 0)
    }

    func delete(_ result: EpworthResult) {
        results.removeAll { $0.id == result.id }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(results) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Non-diagnostic descriptors

    /// A neutral self-tracking band — intentionally *not* a clinical screen.
    /// We report the score and a soft descriptor; we never tell the user they
    /// have a disorder (that would be a device claim). High + persistent scores
    /// are nudged toward a clinician, not labeled.
    static func band(for score: Int) -> String {
        switch score {
        case ..<6:   return "Lower — well rested"
        case 6...10: return "Average daytime sleepiness"
        case 11...15: return "Above average — noticeable"
        default:     return "High daytime sleepiness"
        }
    }

    /// A gentle, non-diagnostic nudge shown under a high score.
    static func note(for score: Int) -> String? {
        score > 10
            ? "A score this high, especially if it stays high over weeks, is worth bringing up with a clinician."
            : nil
    }
}
