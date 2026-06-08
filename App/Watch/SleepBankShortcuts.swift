//
//  SleepBankShortcuts.swift
//  SleepBank Watch App
//
//  Registers the nap intents with Siri and the Shortcuts app, with spoken
//  phrases. Auto-discovered — no Info.plist wiring needed.
//

import AppIntents

struct SleepBankShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartNapIntent(),
            phrases: [
                "Start a nap with \(.applicationName)",
                "Start a power nap in \(.applicationName)",
                "Begin a \(.applicationName) nap",
                "Take a nap with \(.applicationName)",
            ],
            shortTitle: "Start Nap",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: StopNapIntent(),
            phrases: [
                "Stop my \(.applicationName) nap",
                "End my nap in \(.applicationName)",
                "Wake me up in \(.applicationName)",
            ],
            shortTitle: "Stop Nap",
            systemImageName: "stop.fill"
        )
    }
}
