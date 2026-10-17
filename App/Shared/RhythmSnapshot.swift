import Foundation
import SleepBankCore

typealias RhythmSnapshot = AlertnessSnapshot

extension AlertnessSnapshot {
    // MARK: - App Group persistence

    func save() {
        SharedStore.rhythmSnapshot = try? JSONEncoder().encode(self)
        SharedStore.morningLightStreak = morningLightStreak
    }

    static func load() -> RhythmSnapshot? {
        guard let data = SharedStore.rhythmSnapshot else { return nil }
        return try? JSONDecoder().decode(RhythmSnapshot.self, from: data)
    }
}
