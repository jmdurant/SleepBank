//
//  PlanModels.swift
//  SleepBank
//
//  Shared plan model + the per-day plan store, so the alertness curve and Today's
//  Plan agree on the selected day and the naps/walks/workouts planned for each day.
//

import SwiftUI
import SleepBankCore

/// A planned intervention kind.
enum Intervention: String, CaseIterable, Identifiable, Codable {
    case nap, walk, workout
    var id: String { rawValue }
    var label: String { self == .nap ? "Nap" : (self == .walk ? "Walk" : "Workout") }
    var icon: String {
        switch self {
        case .nap:     return "moon.zzz.fill"
        case .walk:    return "figure.walk"
        case .workout: return "figure.run"
        }
    }
    var tint: Color {
        switch self {
        case .nap:     return .mint
        case .walk:    return .orange
        case .workout: return .pink
        }
    }
}

/// One planned intervention. Multiples of any kind are allowed.
struct PlanItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: Intervention
    var napType: NapType = .power
    var at: Date?
    var minutes: Double
    var outdoors: Bool
    static func make(_ kind: Intervention) -> PlanItem {
        PlanItem(kind: kind, minutes: kind == .workout ? 60 : 30, outdoors: kind != .workout)
    }
}

/// The day the user is viewing/planning, plus the plan saved for each day. Shared so
/// the curve and Today's Plan stay in sync as you arrow/calendar across days.
@Observable
final class DayPlanStore {
    static let shared = DayPlanStore()

    var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    private var byDay: [Date: [PlanItem]] = [:]

    private struct Entry: Codable { var day: Date; var items: [PlanItem] }
    private static let key = "dayPlans"

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        for e in entries where e.day >= today { byDay[key(e.day)] = e.items }   // drop past days
    }

    private func key(_ d: Date) -> Date { Calendar.current.startOfDay(for: d) }

    func plan(for date: Date) -> [PlanItem] { byDay[key(date)] ?? [] }
    func setPlan(_ items: [PlanItem], for date: Date) {
        byDay[key(date)] = items
        persist()
    }

    private func persist() {
        let entries = byDay.map { Entry(day: $0.key, items: $0.value) }
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }

    /// Days from today to the selected date (0 = today).
    var selectedOffset: Int {
        Calendar.current.dateComponents([.day], from: key(Date()), to: key(selectedDate)).day ?? 0
    }

    func shift(by days: Int) {
        select(Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate)
    }

    /// Clamp into [today, today+14] and snap to start of day.
    func select(_ date: Date) {
        let today = key(Date())
        let maxDay = Calendar.current.date(byAdding: .day, value: 14, to: today) ?? today
        selectedDate = max(today, min(key(date), maxDay))
    }
}
