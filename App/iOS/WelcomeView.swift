//
//  WelcomeView.swift
//  SleepBank
//
//  The guided start — shown once on first launch (skippable). A couple of questions
//  capture the user's typical schedule (bedtime, wake, sleep need) so the Alertness
//  Score is anchored to their own body clock from day one, rather than an average
//  chronotype. Pre-fills from Apple Health when it's there. Editable later in Settings.
//

import SwiftUI

struct WelcomeView: View {
    var onDone: () -> Void

    @State private var bedtime = Self.dateFromMinutes(23 * 60)
    @State private var wake = Self.dateFromMinutes(7 * 60)
    @State private var need = 8.0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "bolt.fill").font(.system(size: 44)).foregroundStyle(.indigo)
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

                    Button { saveAndFinish() } label: {
                        Text("Get started").font(.headline).frame(maxWidth: .infinity).padding()
                            .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button("Skip for now") { onDone() }
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding()
            }
            .task {
                if !loaded { prefill(); loaded = true }
            }
        }
    }

    private func row(_ icon: String, _ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.indigo).frame(width: 26)
            Text(title).font(.subheadline)
            Spacer()
            control()
        }
    }

    // MARK: - Prefill + save

    private func prefill() {
        let p = SleepProfile.shared
        if p.isSet {
            bedtime = Self.dateFromMinutes(p.bedtimeMinutes)
            wake = Self.dateFromMinutes(p.wakeMinutes)
            need = p.needHours
            return
        }
        // Best-effort from Apple Health: last night's bedtime/wake + the rolling average.
        let health = HealthKitService.shared
        if let bt = health.lastNightSleep?.bedtime { bedtime = bt }
        if let wt = health.lastNightSleep?.wakeTime { wake = wt }
        let avg = health.sleepAverage7Day
        if avg > 0 { need = (avg * 2).rounded() / 2 }
    }

    private func saveAndFinish() {
        SleepProfile.shared.update(bedtime: Self.minutesFromDate(bedtime),
                                   wake: Self.minutesFromDate(wake),
                                   need: need)
        AlertnessProvider.publishSnapshot()
        onDone()
    }

    // MARK: - Minutes <-> Date

    private static func dateFromMinutes(_ m: Int) -> Date {
        Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(m * 60))
    }
    private static func minutesFromDate(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
