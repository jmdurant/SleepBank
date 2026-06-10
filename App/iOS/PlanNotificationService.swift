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

    /// Set whenever a notification is tapped, so a cold-started ContentView can route
    /// even if it missed the live post.
    private(set) var pendingRoute: HomeRoute?

    /// Call once at launch so taps route correctly even on cold start.
    func configure() { center.delegate = self }

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
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "😴 Time for your \(type.title.lowercased())"
        content.body = "Settle in now — a nap here keeps you sharp through the rest of the day, no caffeine needed."
        content.sound = .default
        content.userInfo = ["route": "nap"]

        center.removePendingNotificationRequests(withIdentifiers: [napId])
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: napId, content: content, trigger: trigger))
        Self.scheduledNapAt = date
        return true
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
        let route: HomeRoute
        switch response.notification.request.content.userInfo["route"] as? String {
        case "plan":     route = .plan
        case "winddown": route = .windDown
        default:         return
        }
        pendingRoute = route
        await MainActor.run { NotificationCenter.default.post(name: .openPlan, object: route) }
    }
}
