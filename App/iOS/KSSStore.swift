//
//  KSSStore.swift
//  SleepBank
//
//  The Karolinska Sleepiness Scale (KSS) — a single 1–9 rating of how sleepy you
//  feel *right now* (1 = extremely alert, 9 = fighting sleep). It's the standard
//  momentary sleepiness measure, free to use, and the natural pre/post companion to
//  a nap: a good nap should bring the number *down*. We take it before a nap and
//  again at the recap, and show the change — the kind of paired outcome the
//  alertness/biofeedback evidence base wants (docs/FDA_PATH.md).
//

import Foundation

struct KSSSession: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    var pre: Int        // 1–9
    var post: Int?      // 1–9

    /// Negative = more alert after the nap (the good direction).
    var delta: Int? { post.map { $0 - pre } }

    init(id: UUID = UUID(), date: Date, pre: Int, post: Int? = nil) {
        self.id = id
        self.date = date
        self.pre = pre
        self.post = post
    }
}

@Observable
final class KSSStore {
    static let shared = KSSStore()

    /// The 9 anchored levels.
    static let levels = [
        (1, "Extremely alert"),
        (2, "Very alert"),
        (3, "Alert"),
        (4, "Rather alert"),
        (5, "Neither alert nor sleepy"),
        (6, "Some signs of sleepiness"),
        (7, "Sleepy, but no effort to stay awake"),
        (8, "Sleepy, some effort to stay awake"),
        (9, "Very sleepy, fighting sleep"),
    ]

    static func label(for value: Int) -> String {
        levels.first { $0.0 == value }?.1 ?? "—"
    }

    private(set) var sessions: [KSSSession] = [] {
        didSet { save() }
    }
    /// The id of a started-but-not-yet-completed check-in (survives app relaunch so
    /// the recap can prompt for the "after" rating even after a long nap).
    private(set) var openSessionID: UUID? {
        didSet { UserDefaults.standard.set(openSessionID?.uuidString, forKey: openKey) }
    }

    private let key = "kssSessions"
    private let openKey = "kssOpenSession"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([KSSSession].self, from: data) {
            sessions = decoded.sorted { $0.date > $1.date }
        }
        if let raw = UserDefaults.standard.string(forKey: openKey) {
            openSessionID = UUID(uuidString: raw)
        }
    }

    var latest: KSSSession? { sessions.first }

    /// True when a nap's "before" rating is logged but the "after" isn't yet.
    var hasOpenSession: Bool {
        guard let id = openSessionID else { return false }
        return sessions.first { $0.id == id }?.post == nil
    }

    @discardableResult
    func startSession(pre value: Int) -> UUID {
        let session = KSSSession(date: Date(), pre: value)
        sessions.insert(session, at: 0)
        openSessionID = session.id
        return session.id
    }

    /// Complete the open session with the "after" rating.
    func completeOpenSession(post value: Int) {
        guard let id = openSessionID,
              let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].post = value
        openSessionID = nil
    }

    func cancelOpenSession() { openSessionID = nil }

    func delete(_ session: KSSSession) {
        sessions.removeAll { $0.id == session.id }
        if openSessionID == session.id { openSessionID = nil }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
