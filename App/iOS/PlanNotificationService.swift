//
//  PlanNotificationService.swift
//  SleepBank
//
//  A gentle morning notification that delivers "Today's Plan" — the nudge that
//  turns the day's predicted readiness into action. Tapping it opens the plan
//  (computed fresh). Re-scheduled on each app open so the teaser and time track
//  your latest sleep / wake time.
//

import Foundation
import UserNotifications
import SleepBankCore

extension Notification.Name {
    static let openPlan = Notification.Name("sleepbank.openPlan")
    static let openHistory = Notification.Name("sleepbank.openHistory")
}

final class PlanNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PlanNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let id = "dailyPlan"

    private let windDownId = "windDown"
    private let napId = "scheduledNap"

    /// The user-scheduled nap time for today (set from the alertness curve's "+"),
    /// surfaced so the plan/UI can reflect it. Cleared on a new day.
    static var scheduledNapAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "scheduledNapAt")
            guard t > 0 else { return nil }
            let date = Date(timeIntervalSinceReferenceDate: t)
            return Calendar.current.isDateInToday(date) ? date : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSinceReferenceDate ?? 0, forKey: "scheduledNapAt")
        }
    }

    /// The scheduled nap's type, so the Recap can rebuild its curve effect.
    static var scheduledNapType: NapType {
        get { NapType(rawValue: UserDefaults.standard.string(forKey: "scheduledNapType") ?? "") ?? .power }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "scheduledNapType") }
    }

    /// Set whenever a notification is tapped, so a cold-started ContentView can route
    /// even if it missed the live post.
    private(set) var pendingRoute: HomeRoute?

    /// Call once at launch so taps route correctly even on cold start, and register
    /// the action buttons (Start Nap / Start Walk / Start Workout).
    func configure() {
        center.delegate = self
        func cat(_ id: String, _ actionID: String, _ title: String) -> UNNotificationCategory {
            UNNotificationCategory(identifier: id,
                                   actions: [UNNotificationAction(identifier: actionID, title: title, options: [.foreground])],
                                   intentIdentifiers: [], options: [])
        }
        center.setNotificationCategories([
            cat("NAP_REMINDER", "START_NAP", "Start Nap"),
            cat("WALK_REMINDER", "START_WALK", "Start Walk"),
            cat("WORKOUT_REMINDER", "START_WORKOUT", "Start Workout"),
        ])
    }

    /// Ask for permission (once) and schedule the morning plan + evening wind-down
    /// notifications, timed off the user's recent wake time when known.
    func requestAndSchedule() async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        if Self.morningPlanEnabled { scheduleMorningPlan() }
        else { center.removePendingNotificationRequests(withIdentifiers: [id]) }
        if Self.windDownReminderEnabled { scheduleWindDown() }
        else { center.removePendingNotificationRequests(withIdentifiers: [windDownId]) }
    }

    /// Per-notification on/off (default on). Toggled from Settings; call
    /// requestAndSchedule() after changing.
    static var morningPlanEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notifMorningPlan") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifMorningPlan") }
    }
    static var windDownReminderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notifWindDown") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notifWindDown") }
    }

    func scheduleMorningPlan() {
        let content = UNMutableNotificationContent()
        content.title = "☀️ Today's Plan"
        content.body = teaser()
        content.sound = .default
        content.userInfo = ["route": "plan"]
        schedule(id: id, content: content, fire: morningFireTime())
    }

    func scheduleWindDown() {
        let content = UNMutableNotificationContent()
        content.title = "🌙 Time to wind down"
        content.body = "Dim the lights, screens off soon — protect tonight's sleep so tomorrow starts higher."
        content.sound = .default
        content.userInfo = ["route": "winddown"]
        schedule(id: windDownId, content: content, fire: windDownFireTime())
    }

    /// Schedule a one-shot reminder for a nap the user picked off the alertness
    /// curve. Replaces any previously-scheduled nap. Returns false if the time is in
    /// the past or notifications are denied.
    @discardableResult
    func scheduleNap(at date: Date, type: NapType) async -> Bool {
        let interval = date.timeIntervalSinceNow
        guard interval > 60 else { return false }
        Self.scheduledNapType = type
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "😴 Time for your \(type.title.lowercased())"
        content.body = "Settle in now — a nap here keeps you sharp through the rest of the day, no caffeine needed."
        content.sound = .default
        content.userInfo = ["route": "nap"]
        content.categoryIdentifier = "NAP_REMINDER"

        center.removePendingNotificationRequests(withIdentifiers: [napId])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: napId, content: content, trigger: trigger))
        Self.scheduledNapAt = date
        return true
    }

    /// A walk/workout the user scheduled off the curve, surfaced on Today's Plan.
    struct ScheduledActivity: Codable, Identifiable {
        var kind: String       // "Walk" / "Workout"
        var at: Date
        var outdoors: Bool
        var minutes: Double = 30
        var id: String { kind }
    }

    private static let activitiesKey = "scheduledActivities"

    /// Today's scheduled activities (auto-prunes anything not from today).
    static var scheduledActivities: [ScheduledActivity] {
        get {
            guard let data = UserDefaults.standard.data(forKey: activitiesKey),
                  let all = try? JSONDecoder().decode([ScheduledActivity].self, from: data) else { return [] }
            return all.filter { Calendar.current.isDateInToday($0.at) }
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: activitiesKey)
        }
    }

    private func activityId(_ kind: String) -> String { "scheduledActivity-\(kind.lowercased())" }

    /// Schedule a one-shot reminder for a planned walk/workout from the curve, and
    /// record it for Today's Plan.
    @discardableResult
    func scheduleActivity(at date: Date, title: String, outdoors: Bool, minutes: Double = 30) async -> Bool {
        let interval = date.timeIntervalSinceNow
        guard interval > 60 else { return false }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "\(outdoors ? "☀️" : "💪") Time for your \(title.lowercased())"
        content.body = outdoors
            ? "Get outside — the movement lifts you now and the daylight steadies tonight's sleep."
            : "A bit of movement now keeps you sharp through the rest of the day."
        content.sound = .default
        content.userInfo = ["route": "plan"]
        content.categoryIdentifier = title.caseInsensitiveCompare("walk") == .orderedSame ? "WALK_REMINDER" : "WORKOUT_REMINDER"

        center.removePendingNotificationRequests(withIdentifiers: [activityId(title)])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: activityId(title), content: content, trigger: trigger))

        var items = Self.scheduledActivities.filter { $0.kind.caseInsensitiveCompare(title) != .orderedSame }
        items.append(ScheduledActivity(kind: title, at: date, outdoors: outdoors, minutes: minutes))
        Self.scheduledActivities = items
        return true
    }

    func cancelActivity(kind: String) {
        center.removePendingNotificationRequests(withIdentifiers: [activityId(kind)])
        Self.scheduledActivities = Self.scheduledActivities.filter { $0.kind.caseInsensitiveCompare(kind) != .orderedSame }
    }

    func cancelScheduledNap() {
        center.removePendingNotificationRequests(withIdentifiers: [napId])
        Self.scheduledNapAt = nil
    }

    private func schedule(id: String, content: UNMutableNotificationContent, fire: (Int, Int)) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        var comps = DateComponents()
        comps.hour = fire.0
        comps.minute = fire.1
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func clearPending() { pendingRoute = nil }

    // MARK: - Content

    private func teaser() -> String {
        guard let snap = RhythmSnapshot.load() else {
            return "See how to stay sharp today — naps, light, and timing."
        }
        return snap.isShortNight
            ? "After a short night — here's how to get through today well, without reaching for caffeine."
            : "Here's how to stay sharp today and protect tonight's sleep."
    }

    /// ~20 min after the most recent wake time, else 7:30.
    private func morningFireTime() -> (Int, Int) {
        guard let snap = RhythmSnapshot.load() else { return (7, 30) }
        let fire = snap.wakeTime.addingTimeInterval(20 * 60)
        let c = Calendar.current.dateComponents([.hour, .minute], from: fire)
        return (c.hour ?? 7, c.minute ?? 30)
    }

    /// ~15.5 h after the recent wake time (the plan's wind-down marker), else 22:00.
    private func windDownFireTime() -> (Int, Int) {
        guard let snap = RhythmSnapshot.load() else { return (22, 0) }
        let fire = snap.wakeTime.addingTimeInterval(15.5 * 3600)
        let c = Calendar.current.dateComponents([.hour, .minute], from: fire)
        return (c.hour ?? 22, c.minute ?? 0)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        // Action buttons: ask the watch to begin a real workout (best-effort).
        switch response.actionIdentifier {
        case "START_WALK":    PhoneConnectivity.shared.startWorkout("walk")
        case "START_WORKOUT": PhoneConnectivity.shared.startWorkout("workout")
        default: break
        }
        // Where to open the app.
        let routeStr = response.actionIdentifier == "START_NAP"
            ? "nap" : response.notification.request.content.userInfo["route"] as? String
        let route: HomeRoute
        switch routeStr {
        case "nap":      route = .nap
        case "winddown": route = .windDown
        case "daylight": route = .daylight
        default:         route = .plan
        }
        pendingRoute = route
        await MainActor.run { NotificationCenter.default.post(name: .openPlan, object: route) }
    }
}
