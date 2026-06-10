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

    /// Set whenever a plan notification is tapped, so a cold-started ContentView can
    /// route to the plan even if it missed the live post.
    private(set) var pendingPlan = false

    /// Call once at launch so taps route correctly even on cold start.
    func configure() { center.delegate = self }

    /// Ask for permission (once) and schedule the daily morning notification,
    /// timed ~20 min after the user's recent wake time when we know it.
    func requestAndSchedule() async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        schedule()
    }

    func schedule() {
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "☀️ Today's Plan"
        content.body = teaser()
        content.sound = .default
        content.userInfo = ["route": "plan"]

        let (hour, minute) = fireTime()
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func clearPending() { pendingPlan = false }

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
    private func fireTime() -> (Int, Int) {
        guard let snap = RhythmSnapshot.load() else { return (7, 30) }
        let fire = snap.wakeTime.addingTimeInterval(20 * 60)
        let c = Calendar.current.dateComponents([.hour, .minute], from: fire)
        return (c.hour ?? 7, c.minute ?? 30)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.userInfo["route"] as? String == "plan" else { return }
        pendingPlan = true
        await MainActor.run { NotificationCenter.default.post(name: .openPlan, object: nil) }
    }
}
