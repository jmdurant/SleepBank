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
}

final class PlanNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PlanNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let id = "dailyPlan"

    private let windDownId = "windDown"
    private static let reminders = PlanReminderStore()
    static var scheduledItems: [PlanReminder] { reminders.upcoming(onOrAfter: Date()) }
    private(set) var lastScheduleError: String?

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

    /// A plan item owns its reminder. Adding another of the same kind preserves
    /// all existing reminders; rescheduling this ID replaces only this item.
    @discardableResult
    func schedule(_ item: PlanReminder) async -> Bool {
        lastScheduleError = nil
        guard item.at.timeIntervalSinceNow > 60 else {
            lastScheduleError = "Choose a time at least a minute from now."
            return false
        }
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                lastScheduleError = "Allow notifications in Settings to receive plan reminders. Your plan is still saved."
                return false
            }
            let content = UNMutableNotificationContent()
            content.title = "Time for your \(item.title.lowercased())"
            content.body = item.kind == .nap ? "Your planned nap is coming up. Open SleepBank when you're ready."
                : "Your planned \(Int(item.minutes))-minute \(item.title.lowercased()) is coming up."
            content.sound = .default
            content.userInfo = ["route": item.kind == .nap ? "nap" : "plan", "planItemID": item.id.uuidString,
                                "napType": item.napType.rawValue]
            switch item.kind {
            case .nap: content.categoryIdentifier = "NAP_REMINDER"
            case .walk: content.categoryIdentifier = "WALK_REMINDER"
            case .workout: content.categoryIdentifier = "WORKOUT_REMINDER"
            }
            let interval = item.at.timeIntervalSinceNow
            guard interval > 0 else {
                lastScheduleError = "That reminder time has passed. Choose a new time."
                return false
            }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try await center.add(UNNotificationRequest(identifier: item.notificationID, content: content, trigger: trigger))
            if let oldID = Self.reminders.all().first(where: { $0.id == item.id })?.legacyNotificationID {
                center.removePendingNotificationRequests(withIdentifiers: [oldID])
            }
            Self.reminders.upsert(item)
            return true
        } catch {
            lastScheduleError = "Couldn't schedule the reminder: \(error.localizedDescription)"
            return false
        }
    }

    func cancelReminder(id: UUID) {
        guard let item = Self.reminders.all().first(where: { $0.id == id }) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [item.notificationID] + [item.legacyNotificationID].compactMap { $0 })
        Self.reminders.remove(id: id)
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
        guard let snap = RhythmSnapshot.load(), snap.rebuild() != nil else {
            return "See how to stay sharp today — naps, light, and timing."
        }
        return snap.isShortNight
            ? "After a short night — here's how to get through today well, without reaching for caffeine."
            : "Here's how to stay sharp today and protect tonight's sleep."
    }

    /// ~20 min after the most recent wake time, else 7:30.
    private func morningFireTime() -> (Int, Int) {
        guard let snap = RhythmSnapshot.load(), snap.rebuild() != nil else { return (7, 30) }
        let fire = snap.wakeTime.addingTimeInterval(20 * 60)
        let c = Calendar.current.dateComponents([.hour, .minute], from: fire)
        return (c.hour ?? 7, c.minute ?? 30)
    }

    /// ~15.5 h after the recent wake time (the plan's wind-down marker), else 22:00.
    private func windDownFireTime() -> (Int, Int) {
        guard let snap = RhythmSnapshot.load(), snap.rebuild() != nil else { return (22, 0) }
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
