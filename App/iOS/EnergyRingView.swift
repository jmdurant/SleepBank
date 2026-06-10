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
    var body: some View {
        // Re-evaluate each minute so the battery tracks the day (dip, naps, drain).
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let rhythm = AlertnessProvider.rhythm(now: now)
            let nowLevel = rhythm.level(at: now)
            // While a plan is being built on the curve, preview the peak it would reach.
            let preview = PlanPreview.shared
            let charging = (preview.level ?? -1) > nowLevel + 0.01
            let shown = charging ? (preview.level ?? nowLevel) : nowLevel
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.subheadline).foregroundStyle(.yellow)
                    Text("Alert Score").font(.headline)
                }
                NavigationLink(value: HomeRoute.alertness) {
                    ring(level: shown, now: now, peakTime: charging ? preview.peakTime : nil)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    // MARK: - Ring

    private func ring(level: Double, now: Date, peakTime: Date?) -> some View {
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
                if let peakTime {
                    Label("peak \(peakTime, format: .dateTime.hour().minute())", systemImage: "bolt.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.mint)
                } else {
                    Text(AlertnessProvider.phaseLabel(now))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
