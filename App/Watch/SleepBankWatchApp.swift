//
//  SleepBankWatchApp.swift
//  SleepBank Watch App
//

import SwiftUI
import WatchKit

final class SleepBankWatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        NapController.shared.alarm.adopt(extendedRuntimeSession)
    }
}

@main
struct SleepBankWatchApp: App {
    @WKApplicationDelegateAdaptor(SleepBankWatchDelegate.self) private var appDelegate

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
    @State private var workout = ActivityWorkoutService.shared

    var body: some View {
        NapSessionView()
            .task { WatchConnectivityService.refreshPlanSummary() }
            .onOpenURL { url in
                switch url.host {
                case "daylight": showDaylight = true
                case "plan":     showPlan = true
                default:         break
                }
            }
            .sheet(isPresented: $showDaylight) { WatchDaylightView() }
            .sheet(isPresented: $showPlan) { NavigationStack { WatchDayPlanView() } }
            // A reminder's "Start Walk/Workout" action started a real workout.
            .sheet(isPresented: Binding(get: { workout.isActive }, set: { if !$0 { workout.stop() } })) {
                WorkoutRunningView()
            }
    }
}
