import Foundation

public struct PlanReminder: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case nap, walk, workout }
    public let id: UUID
    public let kind: Kind
    public let at: Date
    public let napType: NapType
    public let outdoors: Bool
    public let minutes: Double
    /// Retain the old notification ID during migration so cancellation also removes it.
    public let legacyNotificationID: String?
    public var notificationID: String { "plan-\(id.uuidString)" }
    public var title: String {
        switch kind {
        case .nap: return napType.title
        case .walk: return "Walk"
        case .workout: return "Workout"
        }
    }

    public init(id: UUID, kind: Kind, at: Date, napType: NapType = .power,
                outdoors: Bool = false, minutes: Double = 30, legacyNotificationID: String? = nil) {
        self.id = id; self.kind = kind; self.at = at; self.napType = napType
        self.outdoors = outdoors; self.minutes = minutes; self.legacyNotificationID = legacyNotificationID
    }
}

/// Durable reminders keyed by the originating plan item, independent of day or kind.
public final class PlanReminderStore {
    private let defaults: UserDefaults
    private let key = "scheduledPlanRemindersV2"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func all() -> [PlanReminder] {
        if let data = defaults.data(forKey: key) {
            return (try? JSONDecoder().decode([PlanReminder].self, from: data)) ?? []
        }
        return migrate()
    }

    public func upcoming(onOrAfter date: Date, calendar: Calendar = .current) -> [PlanReminder] {
        all().filter { $0.at >= calendar.startOfDay(for: date) }.sorted { $0.at < $1.at }
    }

    public func upsert(_ item: PlanReminder) {
        var items = all().filter { $0.id != item.id }
        items.append(item)
        save(items)
    }

    public func remove(id: UUID) { save(all().filter { $0.id != id }) }

    private func save(_ items: [PlanReminder]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }

    private func migrate() -> [PlanReminder] {
        struct OldActivity: Decodable { let kind: String; let at: Date; let outdoors: Bool; let minutes: Double? }
        var items: [PlanReminder] = []
        let stamp = defaults.double(forKey: "scheduledNapAt")
        if stamp > 0 {
            let type = NapType(rawValue: defaults.string(forKey: "scheduledNapType") ?? "") ?? .power
            items.append(PlanReminder(id: UUID(), kind: .nap, at: Date(timeIntervalSinceReferenceDate: stamp),
                                      napType: type, legacyNotificationID: "scheduledNap"))
        }
        if let data = defaults.data(forKey: "scheduledActivities"),
           let old = try? JSONDecoder().decode([OldActivity].self, from: data) {
            items += old.compactMap { item in
                guard let kind = PlanReminder.Kind(rawValue: item.kind.lowercased()) else { return nil }
                return PlanReminder(id: UUID(), kind: kind, at: item.at, outdoors: item.outdoors,
                                    minutes: item.minutes ?? 30, legacyNotificationID: "scheduledActivity-\(item.kind.lowercased())")
            }
        }
        save(items)
        defaults.removeObject(forKey: "scheduledNapAt")
        defaults.removeObject(forKey: "scheduledNapType")
        defaults.removeObject(forKey: "scheduledActivities")
        return items
    }
}
