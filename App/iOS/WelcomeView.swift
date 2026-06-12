//
//  WelcomeView.swift
//  SleepBank
//
//  The guided start — shown once on first launch (skippable) and re-runnable from
//  Settings. Two quick steps:
//   1. Typical schedule (bedtime, wake, sleep need) → anchors the Alertness Score to
//      the user's own body clock (chronotype) from day one.
//   2. Epworth daytime-sleepiness baseline → the on-thesis self-report we track over
//      time (see EpworthStore).
//  Both steps are skippable. Pre-fills the schedule from Apple Health when present.
//

import SwiftUI

struct WelcomeView: View {
    var onDone: () -> Void

    @State private var step = 0
    @State private var bedtime = Self.dateFromMinutes(23 * 60)
    @State private var wake = Self.dateFromMinutes(7 * 60)
    @State private var need = 8.0
    @State private var ess = Array(repeating: -1, count: EpworthStore.situations.count)
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 { scheduleStep }
                else if step == 1 { epworthStep }
                else { PermissionsPrimingView(onDone: onDone) }
            }
            .task { if !loaded { prefill(); loaded = true } }
        }
    }

    // MARK: - Step 1: typical schedule

    private var scheduleStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "bolt.fill").font(.system(size: 44)).foregroundStyle(.ocean)
                    Text("Welcome to SleepBank").font(.title2.bold())
                    Text("A couple of quick questions so your Alertness Score is tuned to *your* body clock — when it peaks, dips, and winds down.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                VStack(spacing: 18) {
                    row("bed.double.fill", "When do you usually go to sleep?") {
                        DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute).labelsHidden()
                    }
                    Divider()
                    row("sunrise.fill", "When do you usually wake up?") {
                        DatePicker("", selection: $wake, displayedComponents: .hourAndMinute).labelsHidden()
                    }
                    Divider()
                    row("moon.zzz.fill", "How much sleep do you need?") {
                        HStack(spacing: 8) {
                            Text(String(format: "%.1f h", need)).font(.body.monospacedDigit().weight(.medium))
                            Stepper("", value: $need, in: 4...12, step: 0.5).labelsHidden()
                        }
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                Text("This sets when your curve peaks and dips. You can change it anytime in Settings.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

                Button { saveProfile(); step = 1 } label: {
                    Text("Next").font(.headline).frame(maxWidth: .infinity).padding()
                        .background(.ocean.gradient, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button("Skip for now") { step = 2 }
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    // MARK: - Step 2: Epworth baseline

    private var epworthStep: some View {
        Form {
            Section {
                Text("One more — how likely are you to doze off in each situation (not just feel tired)? This sets your daytime-sleepiness baseline.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Step 2 of 2 · Daytime sleepiness")
            }
            ForEach(Array(EpworthStore.situations.enumerated()), id: \.offset) { i, situation in
                Section {
                    Picker(selection: essBinding(i)) {
                        ForEach(EpworthStore.choices, id: \.0) { value, label in Text(label).tag(value) }
                    } label: {
                        Text(situation)
                    }
                    .pickerStyle(.menu)
                }
            }
            Section {
                Button {
                    if !ess.contains(-1) { EpworthStore.shared.record(answers: ess) }
                    step = 2
                } label: {
                    Text(ess.contains(-1) ? "Answer all 8 to continue" : "Next").frame(maxWidth: .infinity)
                }
                .disabled(ess.contains(-1))
                Button("Skip this") { step = 2 }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Almost done")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func row(_ icon: String, _ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.ocean).frame(width: 26)
            Text(title).font(.subheadline)
            Spacer()
            control()
        }
    }

    private func essBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { ess[i] }, set: { ess[i] = $0 })
    }

    private func prefill() {
        let p = SleepProfile.shared
        if p.isSet {
            bedtime = Self.dateFromMinutes(p.bedtimeMinutes)
            wake = Self.dateFromMinutes(p.wakeMinutes)
            need = p.needHours
            return
        }
        let health = HealthKitService.shared
        if let bt = health.lastNightSleep?.bedtime { bedtime = bt }
        if let wt = health.lastNightSleep?.wakeTime { wake = wt }
        let avg = health.sleepAverage7Day
        if avg > 0 { need = (avg * 2).rounded() / 2 }
    }

    private func saveProfile() {
        SleepProfile.shared.update(bedtime: Self.minutesFromDate(bedtime),
                                   wake: Self.minutesFromDate(wake),
                                   need: need)
        AlertnessProvider.publishSnapshot()
    }

    private static func dateFromMinutes(_ m: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(m * 60))
    }
    private static func minutesFromDate(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
