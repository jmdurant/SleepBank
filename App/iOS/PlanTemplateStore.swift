//
//  PlanTemplateStore.swift
//  SleepBank
//
//  Saved day-plan templates — a named set of naps/walks/workouts at clock times you
//  can re-apply to any day from the alertness curve. Persisted to UserDefaults; seeded
//  with one starter template.
//

import Foundation

struct PlanTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var items: [Spec]

    /// One templated intervention at a wall-clock time (applied to whatever day).
    struct Spec: Codable {
        var kind: String        // "nap" / "walk" / "workout"
        var hour: Int
        var minute: Int
        var minutes: Double      // duration (activities)
        var outdoors: Bool
        var napType: String      // "power" / "cycle"
    }
}

@Observable
final class PlanTemplateStore {
    static let shared = PlanTemplateStore()

    private(set) var templates: [PlanTemplate] = []
    private static let key = "planTemplates"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([PlanTemplate].self, from: data) {
            templates = decoded
        }
        if templates.isEmpty { templates = [Self.starter]; persist() }
    }

    func add(_ template: PlanTemplate) { templates.append(template); persist() }
    func delete(_ template: PlanTemplate) { templates.removeAll { $0.id == template.id }; persist() }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(templates), forKey: Self.key)
    }

    /// Seed: a morning walk, an afternoon power nap, an evening workout, an after-dinner walk.
    static let starter = PlanTemplate(name: "Full day", items: [
        .init(kind: "walk",    hour: 6,  minute: 55, minutes: 30, outdoors: true,  napType: "power"),
        .init(kind: "nap",     hour: 15, minute: 0,  minutes: 20, outdoors: false, napType: "power"),
        .init(kind: "workout", hour: 17, minute: 0,  minutes: 60, outdoors: false, napType: "power"),
        .init(kind: "walk",    hour: 18, minute: 0,  minutes: 30, outdoors: true,  napType: "power"),
    ])
}
