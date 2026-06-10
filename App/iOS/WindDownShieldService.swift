//
//  WindDownShieldService.swift
//  SleepBank
//
//  Wind-Down Mode — shield distracting apps. iOS won't let us *measure* Screen Time
//  (sandboxed, unreadable), but it does let us *enforce*. The shield apply/clear +
//  config live in the shared `WindDownShield` (App Group), so the manual path (here)
//  and the automatic nightly path (the DeviceActivityMonitor extension) agree.
//
//  REQUIRES `com.apple.developer.family-controls` (auto-provisions for development;
//  TestFlight/App Store needs Apple's gated request). See docs/WIND_DOWN_MODE.md.
//

import Foundation
import SwiftUI

#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
import DeviceActivity

@available(iOS 16.0, *)
@Observable
final class WindDownShieldService {
    static let shared = WindDownShieldService()

    private(set) var isAuthorized = false
    private(set) var isShielding = false

    // Stored (so @Observable tracks them) and mirrored to the App Group on change so
    // the extension sees the same config.
    var selection: FamilyActivitySelection = WindDownShield.selection {
        didSet { WindDownShield.selection = selection }
    }
    var mode: WindDownShieldMode = WindDownShield.mode {
        didSet { WindDownShield.mode = mode }
    }
    /// Auto-shield every evening via DeviceActivity (vs. only while wind-down runs).
    var autoSchedule: Bool = UserDefaults.standard.bool(forKey: "windDownAutoSchedule") {
        didSet {
            UserDefaults.standard.set(autoSchedule, forKey: "windDownAutoSchedule")
            autoSchedule ? enableSchedule() : disableSchedule()
        }
    }

    private init() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    var hasSelection: Bool { WindDownShield.hasSelection }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            await MainActor.run { isAuthorized = true }
        } catch {
            await MainActor.run { isAuthorized = false }
        }
    }

    // MARK: - Manual shield (while wind-down runs)

    func shield() {
        guard isAuthorized, hasSelection else { return }
        WindDownShield.apply()
        isShielding = true
    }

    func unshield() {
        WindDownShield.clear()
        isShielding = false
    }

    // MARK: - Automatic nightly schedule (DeviceActivityMonitor extension reacts)

    /// Monitor the evening→morning window; the extension's `intervalDidStart`
    /// applies the shield and `intervalDidEnd` lifts it.
    func enableSchedule() {
        guard isAuthorized else { return }
        let (startH, startM) = windDownTime()
        let (endH, endM) = wakeTime()
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: startH, minute: startM),
            intervalEnd: DateComponents(hour: endH, minute: endM),   // overnight: end < start spans to next day
            repeats: true)
        let center = DeviceActivityCenter()
        try? center.startMonitoring(DeviceActivityName(WindDownShield.activityName), during: schedule)
    }

    func disableSchedule() {
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(WindDownShield.activityName)])
        WindDownShield.clear()
    }

    // Times from the latest synced rhythm snapshot (fallbacks otherwise).
    private func windDownTime() -> (Int, Int) {
        guard let snap = RhythmSnapshot.load() else { return (22, 0) }
        let c = Calendar.current.dateComponents([.hour, .minute], from: snap.wakeTime.addingTimeInterval(15.5 * 3600))
        return (c.hour ?? 22, c.minute ?? 0)
    }
    private func wakeTime() -> (Int, Int) {
        guard let snap = RhythmSnapshot.load() else { return (7, 0) }
        let c = Calendar.current.dateComponents([.hour, .minute], from: snap.wakeTime)
        return (c.hour ?? 7, c.minute ?? 0)
    }
}
#endif
