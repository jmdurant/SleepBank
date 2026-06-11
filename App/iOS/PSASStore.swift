//
//  PSASStore.swift
//  SleepBank
//
//  The Pre-Sleep Arousal Scale (PSAS, Nicassio et al. 1985) — 16 items rating how
//  *aroused* you feel as you try to fall asleep, split into a somatic subscale
//  (heart racing, muscle tension, shortness of breath — the physiology the breathing
//  pacer targets) and a cognitive subscale (racing thoughts, worry). Each item is
//  rated 1–5, so each subscale runs 8–40 and the total 16–80.
//
//  It's a *state* measure (right now), so we administer it as a pre/post pair around
//  the wind-down breathing intervention — the before→after delta is exactly the kind
//  of paired outcome the biofeedback path wants (docs/FDA_PATH.md §3). Kept in-app;
//  HealthKit has no native sleep questionnaire type.
//
//  Licensing: the PSAS is a journal-published academic scale with no commercial
//  licensing-fee gate (unlike Epworth/PSQI/ISI). Copyright still rests with the
//  authors/publisher — confirm against the original 1985 source before a paid release.
//

import Foundation

/// One filled-in PSAS (16 answers, each 1–5).
struct PSASSnapshot: Codable, Equatable {
    let answers: [Int]
    var somatic: Int { answers.prefix(8).reduce(0, +) }    // 8–40
    var cognitive: Int { answers.suffix(8).reduce(0, +) }  // 8–40
    var total: Int { somatic + cognitive }                 // 16–80
}

/// A wind-down check-in: a "before" snapshot, optionally paired with an "after".
struct PSASSession: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    var pre: PSASSnapshot
    var post: PSASSnapshot?

    var totalDelta: Int? { post.map { $0.total - pre.total } }
    var somaticDelta: Int? { post.map { $0.somatic - pre.somatic } }
    var cognitiveDelta: Int? { post.map { $0.cognitive - pre.cognitive } }

    init(id: UUID = UUID(), date: Date, pre: PSASSnapshot, post: PSASSnapshot? = nil) {
        self.id = id
        self.date = date
        self.pre = pre
        self.post = post
    }
}

@Observable
final class PSASStore {
    static let shared = PSASStore()

    /// The 16 PSAS items — first 8 somatic, last 8 cognitive.
    static let items = [
        // Somatic
        "Heart racing, pounding, or beating irregularly",
        "A jittery, nervous feeling in your body",
        "Shortness of breath or labored breathing",
        "Tightness or tension in your muscles",
        "A cold feeling in your hands, feet, or body",
        "An upset, knotted, or nervous feeling in your stomach",
        "Perspiration in your palms or elsewhere",
        "A dry feeling in your mouth or throat",
        // Cognitive
        "Worry about falling asleep",
        "Reviewing or pondering events of the day",
        "Depressing or anxious thoughts",
        "Worrying about problems other than sleep",
        "Being mentally alert, active",
        "Can't shut off your thoughts",
        "Thoughts keep running through your head",
        "Being distracted by sounds or noise around you",
    ]

    static let somaticCount = 8

    /// 1–5 response anchors.
    static let choices = [
        (1, "Not at all"),
        (2, "Slightly"),
        (3, "Moderately"),
        (4, "A lot"),
        (5, "Extremely"),
    ]

    private(set) var sessions: [PSASSession] = [] {
        didSet { save() }
    }

    private let key = "psasSessions"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PSASSession].self, from: data) {
            sessions = decoded.sorted { $0.date > $1.date }
        }
    }

    var latest: PSASSession? { sessions.first }

    /// Begin a check-in with the "before" answers; returns the session id so the
    /// caller can complete it with the "after" answers post-intervention.
    @discardableResult
    func startSession(pre answers: [Int]) -> UUID {
        let session = PSASSession(date: Date(), pre: PSASSnapshot(answers: answers))
        sessions.insert(session, at: 0)
        return session.id
    }

    /// Attach the "after" snapshot to a started session.
    func completeSession(_ id: UUID, post answers: [Int]) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].post = PSASSnapshot(answers: answers)
    }

    func session(id: UUID) -> PSASSession? { sessions.first { $0.id == id } }

    func delete(_ session: PSASSession) {
        sessions.removeAll { $0.id == session.id }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
