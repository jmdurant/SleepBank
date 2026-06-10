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
import SleepBankCore

struct EnergyRingView: View {
    var health = HealthKitService.shared

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
                if scrubLevel != nil {
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
