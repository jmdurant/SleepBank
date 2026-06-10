//
//  SleepBankWatchApp.swift
//  SleepBank Watch App
//

import SwiftUI

@main
struct SleepBankWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

/// Hosts the nap UI and routes the complication deep links (e.g. the morning-light
/// complication → daylight glance).
struct WatchRootView: View {
    @State private var showDaylight = false

    var body: some View {
        NapSessionView()
            .onOpenURL { url in
                if url.host == "daylight" { showDaylight = true }
            }
            .sheet(isPresented: $showDaylight) { WatchDaylightView() }
    }
}
