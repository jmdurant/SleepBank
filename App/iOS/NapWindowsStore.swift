//
//  NapWindowsStore.swift
//  SleepBank
//
//  User-defined "always OK to nap" windows (recurring daily clock times). They
//  override the calendar — a quiet stretch inside a long appointment, a protected
//  lunch — so a nap can be suggested there even when you look booked.
//

import Foundation

@Observable
final class NapWindowsStore {
    static let shared = NapWindowsStore()

    struct Window: Codable, Identifiable, Hashable {
        var id = UUID()
        var startMinutes: Int   // minutes since midnight
        var endMinutes: Int
    }

    private(set) var windows: [Window] = []
    private let key = "napOKWindows"

    private init() { load() }

    func add() {
        windows.append(Window(startMinutes: 13 * 60, endMinutes: 13 * 60 + 30))   // 1:00–1:30 PM
        save()
    }
    func remove(_ window: Window) { windows.removeAll { $0.id == window.id }; save() }
    func setStart(_ window: Window, minutes: Int) { update(window) { $0.startMinutes = minutes } }
    func setEnd(_ window: Window, minutes: Int) { update(window) { $0.endMinutes = minutes } }

    private func update(_ window: Window, _ change: (inout Window) -> Void) {
        guard let i = windows.firstIndex(where: { $0.id == window.id }) else { return }
        change(&windows[i]); save()
    }

    /// Today's windows as concrete `DateInterval`s (only well-formed start < end).
    func todayIntervals(now: Date = Date(), calendar: Calendar = .current) -> [DateInterval] {
        let base = calendar.startOfDay(for: now)
        return windows.compactMap { w in
            guard w.endMinutes > w.startMinutes else { return nil }
            return DateInterval(start: base.addingTimeInterval(TimeInterval(w.startMinutes * 60)),
                                end: base.addingTimeInterval(TimeInterval(w.endMinutes * 60)))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(windows) { UserDefaults.standard.set(data, forKey: key) }
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Window].self, from: data) else { return }
        windows = decoded
    }
}
