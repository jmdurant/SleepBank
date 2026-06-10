//
//  SleepBankPhoneShortcuts.swift
//  SleepBank
//
//  Registers the phone-side intents with Siri and the Shortcuts app (the nap
//  intents live on the watch, where the nap loop runs). Auto-discovered.
//

import AppIntents

struct SleepBankPhoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AlertnessIntent(),
            phrases: [
                "How alert am I with \(.applicationName)",
                "What's my alertness in \(.applicationName)",
                "Check my alertness with \(.applicationName)",
                "Should I nap with \(.applicationName)",
            ],
            shortTitle: "Check Alertness",
            systemImageName: "bolt.fill"
        )
    }
}
