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
    @State private var calendar = CalendarService.shared
    @State private var napWindows = NapWindowsStore.shared
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system
    @AppStorage("sleepBasis") private var sleepBasis: SleepBasis = .auto
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

            Section {
                Toggle("Avoid calendar conflicts", isOn: Binding(
                    get: { calendar.enabled }, set: { calendar.enabled = $0; if $0 { Task { await calendar.requestAccess() } } }))
            } header: {
                Text("Today's Plan")
            } footer: {
                Text("Reads your calendar's busy times so a nap is suggested when you're actually free — never event details.")
            }

            Section {
                ForEach(napWindows.windows) { window in
                    HStack {
                        DatePicker("", selection: timeBinding(window, isStart: true), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("to").foregroundStyle(.secondary)
                        DatePicker("", selection: timeBinding(window, isStart: false), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Spacer()
                    }
                }
                .onDelete { offsets in offsets.map { napWindows.windows[$0] }.forEach(napWindows.remove) }
                Button { napWindows.add() } label: { Label("Add a window", systemImage: "plus") }
            } header: {
                Text("Always OK to nap")
            } footer: {
                Text("These windows override your calendar — a nap can be suggested here even if you're booked (e.g. a quiet stretch during a long appointment).")
            }

            Section {
                Picker("Base today's curve on", selection: $sleepBasis) {
                    ForEach(SleepBasis.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Last night → today")
            } footer: {
                Text("Sleep Score uses duration + quality (needs Apple-Watch sleep tracking). Sleep debt uses hours only — works with Oura, a manual log, or no watch. Auto picks whichever your data supports.")
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Features") {
                NavigationLink(value: HomeRoute.plan) { Label("Today's Plan", systemImage: "list.bullet.clipboard.fill") }
                NavigationLink(value: HomeRoute.daylight) { Label("Daylight", systemImage: "sun.max.fill") }
                NavigationLink(value: HomeRoute.windDown) { Label("Wind Down (screens, lights)", systemImage: "moon.stars.fill") }
                NavigationLink(value: HomeRoute.alertness) { Label("Alert Score", systemImage: "bolt.fill") }
                NavigationLink(value: HomeRoute.epworth) { Label("Daytime Sleepiness check-in", systemImage: "checklist") }
            }

            Section {
                Text("SleepBank is an investigational wellness prototype — it helps you cope with and optimize a short-sleep day, not replace the sleep you need. Not a medical device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private func timeBinding(_ window: NapWindowsStore.Window, isStart: Bool) -> Binding<Date> {
        Binding(
            get: { Self.dateFromMinutes(isStart ? window.startMinutes : window.endMinutes) },
            set: { d in
                let m = Self.minutesFromDate(d)
                if isStart { napWindows.setStart(window, minutes: m) } else { napWindows.setEnd(window, minutes: m) }
            })
    }

    private static func dateFromMinutes(_ m: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(m * 60))
    }
    private static func minutesFromDate(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
