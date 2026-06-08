import Foundation

/// One completed nap. The honest unit of a "deposit": how long you were actually
/// asleep (onset → end), not how long the session ran.
public struct NapRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let type: NapType
    /// When sleep onset was detected, if it was.
    public let onset: Date?
    public let wakeReason: WakeReason?

    public init(id: UUID = UUID(), start: Date, end: Date, type: NapType,
                onset: Date?, wakeReason: WakeReason?) {
        self.id = id
        self.start = start
        self.end = end
        self.type = type
        self.onset = onset
        self.wakeReason = wakeReason
    }

    /// Time actually asleep — the deposit. Zero if onset was never detected.
    public var asleepDuration: TimeInterval {
        guard let onset else { return 0 }
        return max(0, end.timeIntervalSince(onset))
    }

    /// Total time the session ran.
    public var sessionDuration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}
