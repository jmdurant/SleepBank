import Foundation

/// Sample clocks survive relaying; receipt time never makes a cached sample fresh.
enum RelayTimestamp {
    static let freshness: TimeInterval = 10

    static func date(_ value: Any?) -> Date? {
        guard let seconds = value as? TimeInterval, seconds.isFinite, seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func isFresh(_ date: Date?, now: Date = Date(), within: TimeInterval = freshness) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        return age.isFinite && (-2...within).contains(age)
    }

    static func accepts(_ date: Date?, after previous: Date?, now: Date = Date()) -> Bool {
        guard let date, isFresh(date, now: now) else { return false }
        return previous.map { date > $0 } ?? true
    }
}

/// Receive callbacks can enqueue model writes before WatchConnectivity reports idle.
final class RelayWorkTracker {
    private let lock = NSLock()
    private var count = 0
    var isIdle: Bool { lock.lock(); defer { lock.unlock() }; return count == 0 }
    func begin() { lock.lock(); defer { lock.unlock() }; count += 1 }
    func end() { lock.lock(); defer { lock.unlock() }; count = max(0, count - 1) }
}

/// Commands are short-lived and replay-safe, independently of latest-value context.
struct RelayCommandLedger {
    enum Decision: String { case accepted, duplicate, expired, superseded, invalid }
    private(set) var handled: [String]
    private(set) var latestIssuedAt: [String: TimeInterval]
    init(handled: [String] = [], latestIssuedAt: [String: TimeInterval] = [:]) {
        self.handled = handled
        self.latestIssuedAt = latestIssuedAt
    }

    mutating func receive(_ payload: [String: Any], now: Date = Date()) -> Decision {
        guard let id = payload["commandID"] as? String, UUID(uuidString: id) != nil,
              let issued = RelayTimestamp.date(payload["issuedAt"]),
              let expires = RelayTimestamp.date(payload["expiresAt"]),
              expires > issued, expires.timeIntervalSince(issued) <= 60,
              issued.timeIntervalSince(now) <= 2 else { return .invalid }
        let channel: String
        if payload["watchHRMirror"] is Bool { channel = "watchHRMirror" }
        else if payload["startWorkout"] is String { channel = "startWorkout" }
        else { return .invalid }
        if handled.contains(id) { return .duplicate }
        guard expires > now else { return .expired }
        guard issued.timeIntervalSince1970 > (latestIssuedAt[channel] ?? 0) else { return .superseded }
        latestIssuedAt[channel] = issued.timeIntervalSince1970
        handled.append(id)
        handled = Array(handled.suffix(100))
        return .accepted
    }
}

/// A completed trace stays on disk until the receiver confirms durable storage.
struct RelayFileOutbox {
    let directory: URL
    func save(id: UUID, data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(id.uuidString + ".json"), options: .atomic)
    }
    var pending: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func acknowledge(_ id: UUID) throws {
        let url = directory.appendingPathComponent(id.uuidString + ".json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

struct NapRelayState: Codable {
    var sessionID: String?
    var startedAt: Date = .distantPast
    var sequence = 0
    var ended = false

    mutating func receive(_ payload: [String: Any], now: Date = Date()) -> Bool {
        guard let id = payload["napID"] as? String, UUID(uuidString: id) != nil,
              let start = RelayTimestamp.date(payload["napStartedAt"]),
              let at = RelayTimestamp.date(payload["eventAt"]),
              let next = payload["sequence"] as? Int, next > 0,
              let event = payload["napEvent"] as? String,
              ["start", "update", "onset", "end"].contains(event), start <= at,
              at.timeIntervalSince(now) <= 2 else { return false }
        if id != sessionID {
            guard event == "start", start > startedAt,
                  RelayTimestamp.isFresh(at, now: now, within: 60) else { return false }
            sessionID = id; startedAt = start; sequence = 0; ended = false
        }
        guard !ended, next > sequence,
              event == "end" || RelayTimestamp.isFresh(at, now: now, within: 60) else { return false }
        sequence = next
        if event == "end" { ended = true }
        return true
    }

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "napRelayState"),
              let state = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return state
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "napRelayState") } }
}
