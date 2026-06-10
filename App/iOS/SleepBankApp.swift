//
//  SleepBankApp.swift
//  SleepBank
//

import SwiftUI

@main
struct SleepBankApp: App {
    init() {
        // Set the notification delegate early so a cold-start tap routes correctly.
        PlanNotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
