//
//  WindDownShieldService.swift
//  SleepBank
//
//  Wind-Down Mode — shield distracting apps while you wind down. iOS won't let us
//  *measure* Screen Time (sandboxed, unreadable), but it does let us *enforce*:
//  ManagedSettings can shield apps the user picks via FamilyControls. We shield on
//  "Start wind-down" and clear on stop — no monitor extension needed for the manual
//  case (that path runs app-side while authorized).
//
//  REQUIRES the gated `com.apple.developer.family-controls` entitlement (the account
//  holder requests it from Apple; review can take days to months). Until it's
//  granted, authorization simply fails and the feature stays inert — the rest of the
//  app is unaffected. See docs/WIND_DOWN_MODE.md.
//

import Foundation
import SwiftUI

#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings

/// How the picked apps are used.
enum WindDownShieldMode: String, CaseIterable, Identifiable {
    case blocklist   // block the chosen apps
    case allowlist   // "Bare Necessities" — block everything EXCEPT the chosen apps
    var id: String { rawValue }
    var title: String { self == .blocklist ? "Block these" : "Allow only these" }
}

@available(iOS 16.0, *)
@Observable
final class WindDownShieldService {
    static let shared = WindDownShieldService()

    private let store = ManagedSettingsStore(named: .init("sleepbank.winddown"))
    private let selectionKey = "windDownShieldSelection"
    private let modeKey = "windDownShieldMode"

    private(set) var isAuthorized = false
    private(set) var isShielding = false
    var selection = FamilyActivitySelection() {
        didSet { persist() }
    }
    var mode: WindDownShieldMode = .blocklist {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: modeKey) }
    }

    private init() {
        load()
        mode = WindDownShieldMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .blocklist
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    /// Ask for Family Controls authorization (no-op/failure without the entitlement).
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            await MainActor.run { isAuthorized = true }
        } catch {
            await MainActor.run { isAuthorized = false }
        }
    }

    /// Shield the chosen apps/categories (called when wind-down starts).
    func shield() {
        guard isAuthorized, hasSelection else { return }
        switch mode {
        case .blocklist:
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty
                ? nil : .specific(selection.categoryTokens)
        case .allowlist:
            // Bare Necessities: shield ALL apps except the chosen exceptions.
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
        }
        isShielding = true
    }

    /// Lift the shield (called when wind-down stops).
    func unshield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        isShielding = false
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: selectionKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: selectionKey),
              let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return }
        selection = saved
    }
}
#endif
