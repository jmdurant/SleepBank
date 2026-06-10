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
    var store = NapDecisionStore.shared

    var body: some View {
        // Re-evaluate each minute so the battery tracks the day (dip, naps, drain).
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let rhythm = AlertnessProvider.rhythm(now: now)
            let level = rhythm.level(at: now)
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.subheadline).foregroundStyle(.yellow)
                    Text("Alert Score").font(.headline)
                }
                NavigationLink(value: HomeRoute.alertness) {
                    ring(level: level, now: now)
                }
                .buttonStyle(.plain)
                Text(caption(level: level, rhythm: rhythm))
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                bankFooter
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    // MARK: - Ring

    private func ring(level: Double, now: Date) -> some View {
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
                Text(AlertnessProvider.phaseLabel(now))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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

    private func caption(level: Double, rhythm: AlertnessRhythm) -> String {
        if rhythm.isShortNight && level < 0.6 { return "Short night — you're running lower today." }
        if level < 0.45 { return "Low — a nap or some daylight would lift you." }
        if level >= 0.7 { return "Running strong. Tap for your day's curve." }
        return "Holding steady. Tap for your day's curve."
    }

    // MARK: - Descriptive bank

    private var bankFooter: some View {
        HStack(spacing: 14) {
            stat(value: "\(napsToday)", label: napsToday == 1 ? "nap today" : "naps today")
            if streak > 0 {
                Divider().frame(height: 28)
                stat(value: "🔥 \(streak)", label: streak == 1 ? "day" : "day streak")
            }
            Divider().frame(height: 28)
            stat(value: "\(minutesThisWeek)", label: "min this week")
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data (for the bank)

    private var napRecords: [NapRecord] {
        store.records.map {
            NapRecord(id: $0.id, start: $0.start, end: $0.end, type: $0.type,
                      onset: $0.onset, wakeReason: $0.wakeReason)
        }
    }

    private var napsToday: Int { NapBank.count(on: Date(), in: napRecords) }
    private var streak: Int { NapBank.currentStreak(asOf: Date(), in: napRecords) }
    private var minutesThisWeek: Int { NapBank.minutesAsleepLast7Days(endingAt: Date(), in: napRecords) }
}
