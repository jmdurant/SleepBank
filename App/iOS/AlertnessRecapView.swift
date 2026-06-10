//
//  AlertnessRecapView.swift
//  SleepBank
//
//  The day's alertness analysis — the honest "where the day's ceiling came from"
//  story. Last night's sleep sets the ceiling; naps/light/movement claw you back
//  toward it; a better night would lift the whole curve. Reads live during the day
//  ("today so far") and flips to a retrospective in the evening, where the highest-
//  leverage move becomes protecting tonight's sleep.
//

import SwiftUI
import SleepBankCore

struct AlertnessRecapView: View {
    var health = HealthKitService.shared
    var store = NapDecisionStore.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 600)) { context in
            let now = context.date
            let r = AlertnessProvider.rhythm(health: health, store: store, now: now)
            let wake = r.wakeTime
            let dayEnd = wake.addingTimeInterval(17 * 3600)
            let evening = now > wake.addingTimeInterval(13 * 3600)

            // Your sleep sets the ceiling; a rested night is the reference; a nap is
            // the biggest same-day lever still on the table.
            let bare = AlertnessRhythm(wakeTime: wake, sleepDebt: r.sleepDebt)
            let rested = AlertnessRhythm(wakeTime: wake, sleepDebt: 0.05)
            let ceiling = peak(bare, from: wake, to: dayEnd)
            let restedPeak = peak(rested, from: wake, to: dayEnd)
            let reached = peak(r, from: wake, to: min(now, dayEnd))
            let napLevel = napPotential(r, now: now, dayEnd: dayEnd, evening: evening)
            let potential = max(ceiling, napLevel ?? 0)

            VStack(alignment: .leading, spacing: 12) {
                Text(evening ? "Today's Alertness" : "Today's Alertness, so far")
                    .font(.headline)

                bar(reached: reached, ceiling: ceiling, potential: potential, rested: restedPeak)
                legend(hasNap: napLevel != nil)

                VStack(alignment: .leading, spacing: 6) {
                    line(icon: "bed.double.fill", tint: .indigo, text: ceilingLine(score: sleepScore(), ceiling: ceiling))
                    line(icon: "arrow.up.forward", tint: .teal, text: restedLine(ceiling: ceiling, rested: restedPeak))
                    line(icon: evening ? "flag.checkered" : "location.fill", tint: .secondary,
                         text: reachedLine(reached: reached, evening: evening))
                }

                leverChip(napPeak: napLevel.map(pct), evening: evening)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Bar

    /// A zoomed potential bar: filled to where you've reached, a brighter band for what
    /// a nap would add, and a teal tick for the rested-night ceiling.
    private func bar(reached: Double, ceiling: Double, potential: Double, rested: Double) -> some View {
        let lo = 0.35, hi = min(1.0, max(rested, potential) + 0.06)
        func f(_ v: Double) -> Double { min(max((v - lo) / (hi - lo), 0), 1) }
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 16)
                Capsule().fill(.mint.opacity(0.35)).frame(width: w * f(potential), height: 16)   // + a nap
                Capsule().fill(.linearGradient(colors: [.indigo, .blue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * f(reached), height: 16)                                     // reached
                Rectangle().fill(.teal).frame(width: 2.5, height: 24)
                    .offset(x: max(0, w * f(rested) - 1.25))                                      // rested ceiling
            }
        }
        .frame(height: 24)
    }

    private func legend(hasNap: Bool) -> some View {
        HStack(spacing: 12) {
            swatch(.blue, "Reached")
            if hasNap { swatch(.mint.opacity(0.6), "+ a nap") }
            swatch(.teal, "Rested night")
            Spacer()
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func swatch(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Capsule().fill(c).frame(width: 10, height: 6); Text(t) }
    }

    // MARK: - Lines

    private func line(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon).font(.caption2).foregroundStyle(tint).frame(width: 14)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func ceilingLine(score: Int?, ceiling: Double) -> String {
        if let score {
            return "Last night (Sleep Score \(score)) set today's ceiling near \(pct(ceiling))%."
        }
        return "Last night set today's ceiling near \(pct(ceiling))%."
    }

    private func restedLine(ceiling: Double, rested: Double) -> String {
        let gap = max(0, pct(rested) - pct(ceiling))
        if gap < 2 { return "You're near a fully-rested ceiling — last night did its job." }
        return "A fully-rested night would lift the whole curve to ~\(pct(rested))% — about \(gap) points higher."
    }

    private func reachedLine(reached: Double, evening: Bool) -> String {
        evening ? "Today peaked at \(pct(reached))%." : "You've reached \(pct(reached))% so far."
    }

    private func leverChip(napPeak: Int?, evening: Bool) -> some View {
        let (text, icon, tint): (String, String, Color) = {
            if !evening, let napPeak {
                return ("Biggest lever now: a power nap → ~\(napPeak)%", "moon.zzz.fill", .indigo)
            }
            return ("Biggest lever now: protect tonight's sleep — a steady, earlier night lifts tomorrow's whole curve.",
                    "moon.stars.fill", .purple)
        }()
        return Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.vertical, 6).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(tint)
    }

    // MARK: - Model helpers

    private func peak(_ rhythm: AlertnessRhythm, from: Date, to: Date) -> Double {
        guard to > from else { return rhythm.level(at: from) }
        return rhythm.readings(from: from, to: to, step: 1200).map(\.level).max() ?? rhythm.level(at: from)
    }

    /// The best peak a power nap *now* could still reach today, or nil in the evening /
    /// when there's no useful day left to nap into.
    private func napPotential(_ r: AlertnessRhythm, now: Date, dayEnd: Date, evening: Bool) -> Double? {
        guard !evening, now < dayEnd.addingTimeInterval(-2 * 3600) else { return nil }
        let from = now.addingTimeInterval(NapType.power.targetWakeAfterOnset)
        let proj = r.projectedReadings(napType: .power, napAt: now, from: from, to: dayEnd, step: 1200)
        return proj.map(\.level).max()
    }

    private func sleepScore() -> Int? {
        guard let s = health.lastNightSleep, s.totalHours > 0 else { return nil }
        let need = max(health.sleepAverage7Day > 0 ? health.sleepAverage7Day : 7.5, 6)
        return SleepScore.score(
            asleepHours: s.totalHours, needHours: need, efficiency: s.efficiency,
            deepHours: s.deepHours, remHours: s.remHours,
            bedtimeMinutes: s.bedtime.map(BedtimeHistoryStore.minutesFrom6pm),
            normalMinutes: BedtimeHistoryStore.shared.normalMinutes,
            spreadMinutes: BedtimeHistoryStore.shared.spreadMinutes)
    }

    private func pct(_ level: Double) -> Int { Int((level * 100).rounded()) }
}
