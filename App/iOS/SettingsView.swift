//
//  SettingsView.swift
//  SleepBank
//
//  One place to turn the notifications and the main features on/off — the toggles
//  had spread across screens, and the daily notifications had no off switch.
//

import SwiftUI

struct SettingsView: View {
    @State private var noise = NoiseService.shared
    @State private var relax = GuidedRelaxationService.shared
    @State private var morningPlan = PlanNotificationService.morningPlanEnabled
    @State private var windDownReminder = PlanNotificationService.windDownReminderEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Morning plan", isOn: $morningPlan)
                    .onChange(of: morningPlan) { _, v in
                        PlanNotificationService.morningPlanEnabled = v
                        Task { await PlanNotificationService.shared.requestAndSchedule() }
                    }
                Toggle("Evening wind-down reminder", isOn: $windDownReminder)
                    .onChange(of: windDownReminder) { _, v in
                        PlanNotificationService.windDownReminderEnabled = v
                        Task { await PlanNotificationService.shared.requestAndSchedule() }
                    }
            } header: {
                Text("Notifications")
            } footer: {
                Text("The morning nudge fires ~20 min after you wake; the wind-down reminder near your bedtime.")
            }

            Section("During a nap") {
                Toggle("Play relaxing sounds", isOn: Binding(
                    get: { noise.autoPlayDuringNap }, set: { noise.autoPlayDuringNap = $0 }))
                Picker("Guided relaxation", selection: Binding(
                    get: { relax.guide }, set: { relax.guide = $0 })) {
                    ForEach(RelaxationGuide.allCases) { g in Text(g.title).tag(g) }
                }
            }

            Section("Features") {
                NavigationLink(value: HomeRoute.plan) { Label("Today's Plan", systemImage: "list.bullet.clipboard.fill") }
                NavigationLink(value: HomeRoute.daylight) { Label("Daylight", systemImage: "sun.max.fill") }
                NavigationLink(value: HomeRoute.windDown) { Label("Wind Down (screens, lights)", systemImage: "moon.stars.fill") }
                NavigationLink(value: HomeRoute.alertness) { Label("Alertness", systemImage: "bolt.fill") }
            }

            Section {
                Text("SleepBank is an investigational wellness prototype — it helps you cope with and optimize a short-sleep day, not replace the sleep you need. Not a medical device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
