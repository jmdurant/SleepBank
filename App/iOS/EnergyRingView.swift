//
//  EnergyRingView.swift
//  SleepBank
//
//  The home dashboard, in compact tiles: a horizontal "last night" summary on top,
//  then two equal boxes side by side — the Alertness Score ring (left) and today's
//  Daylight (right). Each tile is its own tappable card (and mirrors a widget), so
//  the hero ring no longer dominates the screen. The full curve sits below.
//

import SwiftUI
import WidgetKit
import SleepBankCore

/// Composes the three home tiles. Drop this in place of the old single hero card.
struct HomeDashboard: View {
    var body: some View {
        VStack(spacing: 14) {
            LastNightBox()
            // Equal-size pair: identical width and height; content centered in each so
            // neither overflows nor floats. Ring is sized to fit this height exactly.
            HStack(spacing: 10) {
                AlertnessScoreBox().frame(maxWidth: .infinity)
                DaylightBox().frame(maxWidth: .infinity)
            }
            .frame(height: 166)
        }
    }
}

// MARK: - Last night (horizontal summary)

struct LastNightBox: View {
    var health = HealthKitService.shared
    @State private var showSleepEntry = false

    private var needsEntry: Bool {
        AlertnessProvider.sleepDataLoaded(health: health) && !AlertnessProvider.hasSleepData(health: health)
    }

    var body: some View {
        Group {
            if needsEntry {
                Button { showSleepEntry = true } label: { card }.buttonStyle(.plain)
            } else {
                // Push a detail page for the night (with a back button), like the
                // other home cards — not a tab switch.
                NavigationLink(value: HomeRoute.history) { card }.buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showSleepEntry) { SleepEntrySheet() }
    }

    private var card: some View {
        HStack(spacing: 14) {
            Image(systemName: "bed.double.fill").font(.title2).foregroundStyle(.ocean)
            VStack(alignment: .leading, spacing: 2) {
                Text("Last night").font(.subheadline.weight(.semibold))
                Text(detailLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let s = score {
                VStack(spacing: 0) {
                    Text("\(s)").font(.title2.bold().monospacedDigit()).foregroundStyle(verdictColor(s))
                    Text("Sleep Score").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: needsEntry ? "plus.circle" : "chevron.right")
                    .font(.title3)
                    .foregroundStyle(needsEntry ? AnyShapeStyle(Color.ocean) : AnyShapeStyle(.tertiary))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var detailLine: String {
        if needsEntry { return "Tap to estimate how you slept" }
        guard let s = health.lastNightSleep, s.totalHours > 0 else { return "No sleep recorded" }
        let h = Int(s.totalHours)
        let m = Int((s.totalHours - Double(h)) * 60)
        let dur = m > 0 ? "\(h)h \(m)m asleep" : "\(h)h asleep"
        if let sc = score { return "\(dur) · \(verdict(sc))" }
        return dur
    }

    private var score: Int? {
        guard let s = health.lastNightSleep, s.totalHours > 0 else { return nil }
        let need = max(health.sleepAverage7Day > 0 ? health.sleepAverage7Day : 7.5, 6)
        return SleepScore.score(
            asleepHours: s.totalHours, needHours: need, efficiency: s.efficiency,
            deepHours: s.deepHours, remHours: s.remHours,
            bedtimeMinutes: s.bedtime.map(BedtimeHistoryStore.minutesFrom6pm),
            normalMinutes: BedtimeHistoryStore.shared.normalMinutes,
            spreadMinutes: BedtimeHistoryStore.shared.spreadMinutes)
    }

    private func verdict(_ s: Int) -> String {
        switch s {
        case 85...:   return "great night"
        case 70..<85: return "solid night"
        case 55..<70: return "a bit short"
        default:      return "rough night"
        }
    }
    private func verdictColor(_ s: Int) -> Color {
        switch s {
        case 85...:   return .mint
        case 70..<85: return .ocean
        case 55..<70: return .sand
        default:      return Color(red: 0.72, green: 0.55, blue: 0.32)
        }
    }
}

// MARK: - Alertness Score (compact ring box)

struct AlertnessScoreBox: View {
    var health = HealthKitService.shared
    @State private var showSleepEntry = false
    /// Off until just after load, so the initial value settling in doesn't "draw on"
    /// — only genuine changes during the day (dip, scrub, nap preview) animate.
    @State private var animateRing = false

    private var needsSleepEntry: Bool {
        AlertnessProvider.sleepDataLoaded(health: health) && !AlertnessProvider.hasSleepData(health: health)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let rhythm = AlertnessProvider.rhythm(now: now)
            let nowLevel = rhythm.level(at: now)
            // The curve card scrubs to a time (preview.scrubTime) and previews a plan's
            // peak (preview.level). Reflect both on the ring: scrub wins, else the
            // charging preview, else the right-now level.
            let preview = PlanPreview.shared
            let scrubLevel: Double? = preview.scrubTime.map { rhythm.level(at: $0) }
            let charging = (preview.level ?? -1) > nowLevel + 0.01
            let shown = scrubLevel ?? (charging ? (preview.level ?? nowLevel) : nowLevel)
            let markTime: Date? = preview.scrubTime ?? (charging ? preview.peakTime : nil)
            Group {
                if needsSleepEntry {
                    Button { showSleepEntry = true } label: { box { noDataRing } }.buttonStyle(.plain)
                } else {
                    NavigationLink(value: HomeRoute.alertness) {
                        box { ring(level: shown, now: now, markTime: markTime, scrubbing: scrubLevel != nil) }
                    }.buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showSleepEntry) { SleepEntrySheet() }
        .task {
            // Let the level settle on load without animating, then enable it.
            try? await Task.sleep(for: .milliseconds(800))
            animateRing = true
        }
    }

    private func box<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill").font(.caption).foregroundStyle(.sand)
                Text("Alertness").font(.subheadline.weight(.semibold))
                Spacer()
            }
            // Bias the ring down: open the slack between the title and the ring, and
            // cap the space below it so it sits lower in the tile (not floating high).
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0).frame(maxHeight: 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var noDataRing: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 11)
            VStack(spacing: 2) {
                Image(systemName: "bed.double.fill").font(.body).foregroundStyle(.ocean)
                Text("—").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Estimate").font(.caption2.weight(.semibold)).foregroundStyle(.ocean)
            }
        }
        .frame(width: 110, height: 110)
    }

    private func ring(level: Double, now: Date, markTime: Date?, scrubbing: Bool) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 11)
            Circle()
                .trim(from: 0, to: max(0.001, level))
                .stroke(
                    AngularGradient(colors: tint(for: level), center: .center,
                                    startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(animateRing ? .easeInOut(duration: 0.6) : nil, value: level)
            VStack(spacing: 0) {
                Text("\(AlertnessProvider.pct(level))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText())
                if let markTime, scrubbing {
                    Text(markTime, format: .dateTime.hour().minute())
                        .font(.caption2.weight(.semibold)).foregroundStyle(.ocean)
                } else if let markTime {
                    Label(markTime.formatted(.dateTime.hour().minute()), systemImage: "bolt.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.mint)
                } else {
                    Text(AlertnessProvider.phaseLabel(now))
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 110, height: 110)
    }

    private func tint(for level: Double) -> [Color] {
        switch level {
        case 0.66...:     return [.aqua, .mint]
        case 0.4..<0.66:  return [.ocean, .tide]
        case 0.2..<0.4:   return [.sand, Color(red: 0.82, green: 0.64, blue: 0.40)]
        default:          return [Color(red: 0.72, green: 0.55, blue: 0.32), .sand]
        }
    }
}

// MARK: - Daylight (compact box)

struct DaylightBox: View {
    var health = HealthKitService.shared

    var body: some View {
        let d = health.daylightToday
        let streak = health.morningLightStreak
        let walkMin = health.morningActivityMinutes
        NavigationLink(value: HomeRoute.daylight) {
            VStack(alignment: .leading, spacing: 4) {
                // Header pinned to the top so it lines up with "Alertness"; no chevron
                // (Alertness has none).
                HStack(spacing: 5) {
                    Image(systemName: "sun.max.fill").font(.caption).foregroundStyle(.sand)
                    Text("Daylight").font(.subheadline.weight(.semibold))
                    Spacer()
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(d.total.rounded()))").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("min").font(.subheadline).foregroundStyle(.secondary)
                }
                if d.morning >= 1 {
                    Text("\(Int(d.morning.rounded())) min this morning").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("none yet this morning").font(.caption).foregroundStyle(.secondary)
                }
                // Activity reads parallel to the daylight line, right beneath it.
                if walkMin >= 1 {
                    Text("\(Int(walkMin.rounded())) min activity this morning").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                // Streak fills the bottom of the tile.
                if streak > 0 {
                    Text("🌅 \(streak)-day streak").font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

/// Asked on load when Apple Health has no sleep for last night — your estimate
/// seeds the Alertness Score so it reflects your real night, not a "rested" default.
struct SleepEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Double = 7.0
    @State private var awakenings: Int = 2

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "bed.double.fill").font(.largeTitle).foregroundStyle(.ocean)
                Text("How was last night?")
                    .font(.title3.bold()).multilineTextAlignment(.center)
                Text("We didn't find sleep data from Apple Health. Your estimate becomes an Apple-style Sleep Score so your Alertness Score reflects your real night.")
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
                        .background(.ocean.gradient, in: RoundedRectangle(cornerRadius: 16))
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
                Text(value).font(.title3.monospacedDigit().bold()).foregroundStyle(.ocean)
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
