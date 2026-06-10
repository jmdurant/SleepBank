//
//  CalendarService.swift
//  SleepBank
//
//  Reads the device calendars so the Day Plan suggests a nap in a *free* slot, not
//  on top of a meeting. We only need busy time ranges (never event details), and it
//  can be turned off in Settings.
//

import Foundation
import EventKit

@Observable
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()
    private(set) var authorized = false

    var enabled: Bool = UserDefaults.standard.object(forKey: "calendarConflictCheck") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "calendarConflictCheck") }
    }

    func requestAccess() async {
        guard enabled else { return }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        await MainActor.run { authorized = granted }
    }

    /// Busy intervals from now to end of day — excluding all-day events and anything
    /// marked "free" (so a held-but-available block doesn't block a nap).
    func busyToday(now: Date = Date()) -> [DateInterval] {
        guard enabled, authorized else { return [] }
        let cal = Calendar.current
        let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        guard end > now else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.availability != .free }
            .compactMap { event in
                guard event.endDate > event.startDate else { return nil }
                return DateInterval(start: event.startDate, end: event.endDate)
            }
    }
}
