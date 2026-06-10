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
    @State private var showPlan = false

    var body: some View {
        NapSessionView()
            .onOpenURL { url in
                switch url.host {
                case "daylight": showDaylight = true
                case "plan":     showPlan = true
                default:         break
                }
            }
            .sheet(isPresented: $showDaylight) { WatchDaylightView() }
            .sheet(isPresented: $showPlan) { NavigationStack { WatchDayPlanView() } }
    }
}
