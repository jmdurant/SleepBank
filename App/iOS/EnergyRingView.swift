//
//  EnergyRingView.swift
//  SleepBank
//
//  The home-screen hero: an "energy battery" ring showing your overall predicted
//  alertness right now — it reflects last night's sleep (a short night sits lower),
//  the circadian rhythm (the afternoon dip), naps (a nap visibly lifts it), and
//  morning light. Tap through for the full curve. Beneath it, the descriptive bank:
//  naps today, streak, minutes this week.
//

import SwiftUI
import WidgetKit
import SleepBankCore

struct EnergyRingView: View {
    var health = HealthKitService.shared
    @State private var showSleepEntry = false
    @State private var promptedThisLaunch = false

    /// No real sleep basis yet, and HealthKit has finished loading — so it's a true
    /// "no data" state, not just "still loading."
    private var needsSleepEntry: Bool {
        AlertnessProvider.sleepDataLoaded(health: health) && !AlertnessProvider.hasSleepData(health: health)
    }

    var body: some View {
        // Re-evaluate each minute so the battery tracks the day (dip, naps, drain).
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let rhythm = AlertnessProvider.rhythm(now: now)
            let nowLevel = rhythm.level(at: now)
            // While a plan is being built, preview its peak; while scrubbing the bare
            // curve, show the level at the scrubbed time. Tapping resets to "now".
            let preview = PlanPreview.shared
            let scrubLevel: Double? = preview.scrubTime.map { rhythm.level(at: $0) }
            let charging = (preview.level ?? -1) > nowLevel + 0.01
            let shown = scrubLevel ?? (charging ? (preview.level ?? nowLevel) : nowLevel)
            let markTime: Date? = preview.scrubTime ?? (charging ? preview.peakTime : nil)
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.subheadline).foregroundStyle(.yellow)
                    Text("Alert Score").font(.headline)
                }
                if needsSleepEntry {
                    // No sleep basis → don't show a (misleadingly high) number; ask.
                    Button { showSleepEntry = true } label: { noDataRing }
                        .buttonStyle(.plain)
                } else if scrubLevel != nil {
                    Button { PlanPreview.shared.scrubTime = nil } label: {
                        ring(level: shown, now: now, markTime: markTime, scrubbing: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: HomeRoute.alertness) {
                        ring(level: shown, now: now, markTime: markTime, scrubbing: false)
                    }
                    .buttonStyle(.plain)
                }
                Divider().padding(.top, 2)
                daylightRow()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
        // Popup on load when there's no sleep data — once per launch.
        .onChange(of: needsSleepEntry) { _, needs in
            if needs && !promptedThisLaunch { promptedThisLaunch = true; showSleepEntry = true }
        }
        .onAppear {
            if needsSleepEntry && !promptedThisLaunch { promptedThisLaunch = true; showSleepEntry = true }
        }
        .sheet(isPresented: $showSleepEntry) { SleepEntrySheet() }
    }

    // MARK: - No-data state

    private var noDataRing: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 18)
            VStack(spacing: 4) {
                Image(systemName: "bed.double.fill").font(.title2).foregroundStyle(.indigo)
                Text("—").font(.system(size: 40, weight: .bold, design: .rounded))
                Text("Estimate last night").font(.caption.weight(.semibold)).foregroundStyle(.indigo)
            }
        }
        .frame(width: 180, height: 180)
    }

    // MARK: - Daylight

    private func daylightRow() -> some View {
        let d = health.daylightToday
        let streak = health.morningLightStreak
        let walkMin = health.morningActivityMinutes
        return NavigationLink(value: HomeRoute.daylight) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                    Text("\(Int(d.total.rounded())) min daylight today").font(.caption.weight(.medium)).foregroundStyle(.primary)
                    if d.morning >= 1 { Text("· \(Int(d.morning.rounded())) min AM").font(.caption).foregroundStyle(.secondary) }
                    if walkMin >= 1 { Text("· 🚶 \(Int(walkMin.rounded())) min AM").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if streak > 0 { Text("🌅 \(streak)").font(.caption.weight(.semibold)).foregroundStyle(.primary) }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                if let nudge = daylightNudge(d, walkMinutes: walkMin) {
                    Text(nudge).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func daylightNudge(_ d: DaylightDay, walkMinutes: Double) -> String? {
        if d.morning >= 20 && walkMinutes >= 10 { return "☀️🚶 Morning light + movement — both anchor your rhythm and help you sleep tonight." }
        if d.morning >= 20 { return "☀️ Morning light in — anchors your rhythm and helps you sleep tonight." }
        return nil
    }

    // MARK: - Ring

    private func ring(level: Double, now: Date, markTime: Date?, scrubbing: Bool) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 18)
            Circle()
                .trim(from: 0, to: max(0.001, level))
                .stroke(
                    AngularGradient(colors: tint(for: level), center: .center,
                                    startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: level)
            VStack(spacing: 2) {
                Text("\(AlertnessProvider.pct(level))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let markTime, scrubbing {
                    Label("at \(markTime, format: .dateTime.hour().minute())", systemImage: "hand.draw.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.indigo)
                } else if let markTime {
                    Label("peak \(markTime, format: .dateTime.hour().minute())", systemImage: "bolt.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.mint)
                } else {
                    Text(AlertnessProvider.phaseLabel(now))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 180, height: 180)
    }

    private func tint(for level: Double) -> [Color] {
        switch level {
        case 0.66...:     return [.mint, .teal]      // energized
        case 0.4..<0.66:  return [.indigo, .blue]    // steady
        case 0.2..<0.4:   return [.orange, .yellow]  // dipping
        default:          return [.orange, .pink]    // low
        }
    }

}

/// Asked on load when Apple Health has no sleep for last night — your estimate
/// seeds the Alert Score so it reflects your real night, not a "rested" default.
struct SleepEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Double = 7.0
    @State private var awakenings: Int = 2

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "bed.double.fill").font(.largeTitle).foregroundStyle(.indigo)
                Text("How was last night?")
                    .font(.title3.bold()).multilineTextAlignment(.center)
                Text("We didn't find sleep data from Apple Health. Your estimate becomes an Apple-style Sleep Score so your Alert Score reflects your real night.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

                entryRow("Hours slept", value: String(format: "%.1f h", hours)) {
                    Stepper("", value: $hours, in: 0...14, step: 0.5).labelsHidden()
                }
                entryRow("Times you woke up", value: "\(awakenings)") {
                    Stepper("", value: $awakenings, in: 0...12).labelsHidden()
                }
                Text("Roughly how many times you remember waking — it sets the interruptions part of the score.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)

                Button {
                    save()
                } label: {
                    Text("Save").font(.headline).frame(maxWidth: .infinity).padding()
                        .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func entryRow(_ title: String, value: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(value).font(.title3.monospacedDigit().bold()).foregroundStyle(.indigo)
            }
            Spacer()
            control()
        }
    }

    /// Log the estimate, then refresh everything downstream of the rhythm — the
    /// in-app ring/curve update via @Observable on ManualSleepStore, but the widget
    /// and watch read a saved snapshot, so re-snapshot and reload them too.
    private func save() {
        ManualSleepStore.shared.log(hours: hours, awakenings: awakenings)
        let health = HealthKitService.shared
        let snapshot = RhythmSnapshot(rhythm: AlertnessProvider.rhythm(now: Date()),
                                      morningLightStreak: health.morningLightStreak, updated: Date())
        snapshot.save()
        PhoneConnectivity.shared.sendDailySummary(
            samples: health.lastNightSamples,
            morningLightStreak: health.morningLightStreak,
            rhythmSnapshot: try? JSONEncoder().encode(snapshot))
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}
