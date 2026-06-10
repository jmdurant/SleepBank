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

extension Notification.Name {
    static let openPlan = Notification.Name("sleepbank.openPlan")
}

final class PlanNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PlanNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let id = "dailyPlan"

    private let windDownId = "windDown"

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
        scheduleMorningPlan()
        scheduleWindDown()
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
