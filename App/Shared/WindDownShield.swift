//
//  WindDownShield.swift
//  SleepBank (shared — app + DeviceActivityMonitor extension)
//
//  The shield apply/clear logic + its App Group-backed config, shared so BOTH the
//  app (manual shield) and the DeviceActivityMonitor extension (automatic nightly
//  shield) act on the same selection. Pure FamilyControls/ManagedSettings — no
//  DeviceActivity import (the app schedules; the extension reacts).
//

import Foundation

#if os(iOS)
import FamilyControls
import ManagedSettings

/// How the picked apps are used.
enum WindDownShieldMode: String, CaseIterable, Identifiable {
    case blocklist   // block the chosen apps
    case allowlist   // "Bare Necessities" — block everything EXCEPT the chosen apps
    var id: String { rawValue }
}

enum WindDownShield {
    static let storeName = ManagedSettingsStore.Name("sleepbank.winddown")
    /// DeviceActivity schedule name (wrapped as DeviceActivityName at the call site).
    static let activityName = "sleepbank.winddown.evening"

    private static let appGroup = "group.com.doctordurant.sleepbank"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// The apps the user picked (exceptions in allowlist mode, targets in blocklist).
    static var selection: FamilyActivitySelection {
        get {
            guard let data = defaults?.data(forKey: "wdSelection"),
                  let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
                return FamilyActivitySelection()
            }
            return sel
        }
        set { defaults?.set(try? JSONEncoder().encode(newValue), forKey: "wdSelection") }
    }

    static var mode: WindDownShieldMode {
        get { WindDownShieldMode(rawValue: defaults?.string(forKey: "wdMode") ?? "") ?? .blocklist }
        set { defaults?.set(newValue.rawValue, forKey: "wdMode") }
    }

    static var hasSelection: Bool {
        let s = selection
        return !s.applicationTokens.isEmpty || !s.categoryTokens.isEmpty
    }

    /// Apply the shield per the stored selection + mode.
    static func apply() {
        guard hasSelection else { return }
        let store = ManagedSettingsStore(named: storeName)
        let sel = selection
        switch mode {
        case .blocklist:
            store.shield.applications = sel.applicationTokens.isEmpty ? nil : sel.applicationTokens
            store.shield.applicationCategories = sel.categoryTokens.isEmpty
                ? nil : .specific(sel.categoryTokens)
        case .allowlist:
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: sel.applicationTokens)
        }
    }

    /// Lift the shield.
    static func clear() {
        let store = ManagedSettingsStore(named: storeName)
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }
}
#endif
