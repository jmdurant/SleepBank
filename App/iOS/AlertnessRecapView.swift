//
//  AlertnessRecapView.swift
//  SleepBank
//
//  The day's alertness analysis, in two phases. *Before* the day's peak it looks
//  forward: last night set a ceiling; here's the highest-leverage way to make the
//  most of it. *After* the peak — once the day has largely played out — it becomes a
//  retrospective: it draws the gap a short night opened between your curve and a
//  rested one, fills in green what your naps/light/movement actually recovered, and
//  quantifies it as a single "% recovered."
//

import SwiftUI
import Charts
import SleepBankCore

struct AlertnessRecapView: View {
    var health = HealthKitService.shared
    var store = NapDecisionStore.shared

    private struct P: Identifiable { let id = UUID(); let t: Date; let bare, actual, ideal: Double }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 600)) { context in
            let now = context.date
            let r = AlertnessProvider.rhythm(health: health, store: store, now: now)
            let wake = r.wakeTime
            let dayEnd = wake.addingTimeInterval(17 * 3600)
            let bare = AlertnessRhythm(wakeTime: wake, sleepDebt: r.sleepDebt)
            let rested = AlertnessRhythm(wakeTime: wake, sleepDebt: 0.05)
            let evening = now > wake.addingTimeInterval(13 * 3600)
            // What actually happened, up to now — fills in live through the day.
            let pts = samples(actual: r, bare: bare, rested: rested, from: wake, to: now)
            let gapArea = pts.reduce(0.0) { $0 + max(0, $1.ideal - $1.bare) }
            let fillArea = pts.reduce(0.0) { $0 + max(0, min($1.actual, $1.ideal) - $1.bare) }
            let recovered = gapArea > 0.001 ? Int((fillArea / gapArea * 100).rounded()) : 100
            let napLevel = evening ? nil : napPotential(r, now: now, dayEnd: dayEnd)

            VStack(alignment: .leading, spacing: 10) {
                Text(evening ? "Today's Alertness — recap" : "Today's Alertness, so far").font(.headline)
                headline(recovered: recovered, gapArea: gapArea, evening: evening)
                gapChart(pts)
                legend(hasGain: fillArea > 0.001)
                line("bed.double.fill", .ocean, recapLine(score: sleepScore(), gapArea: gapArea))
                leverChip(napPeak: napLevel.map(pct), evening: evening)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func headline(recovered: Int, gapArea: Double, evening: Bool) -> some View {
        let when = evening ? "today" : "so far"
        let text: String
        if gapArea < 0.6 { text = "Last night did its job — you're near a fully-rested ceiling \(when)." }
        else if recovered < 2 { text = "A short night is costing you alertness \(when) (the grey). Naps, light, and movement are the levers — fill it in." }
        else { text = "Naps, light & movement have recovered **\(recovered)%** of the alertness your short night cost \(when)." }
        return Text(.init(text)).font(.subheadline).foregroundStyle(.primary)
    }

    private func recapLine(score: Int?, gapArea: Double) -> String {
        if gapArea < 0.6 { return "The grey is what a short night would cost — yours was small." }
        let lost = "The grey that's left is the part only a better night fixes — tonight's wind-down is the lever."
        if let score { return "Last night scored \(score). \(lost)" }
        return lost
    }

    // MARK: - The gap image

    private func gapChart(_ pts: [P]) -> some View {
        let lo = max(0, (pts.map(\.bare).min() ?? 0) - 0.03)
        let hi = min(1, (pts.map(\.ideal).max() ?? 1) + 0.03)
        return Chart {
            ForEach(pts) { p in
                AreaMark(x: .value("t", p.t), yStart: .value("lo", p.bare), yEnd: .value("hi", max(p.bare, p.ideal)),
                         series: .value("s", "gap"))
                    .foregroundStyle(.gray.opacity(0.16))
            }
            ForEach(pts) { p in
                AreaMark(x: .value("t", p.t), yStart: .value("lo", p.bare),
                         yEnd: .value("hi", max(p.bare, min(p.actual, p.ideal))),
                         series: .value("s", "fill"))
                    .foregroundStyle(.green.opacity(0.32))
            }
            ForEach(pts) { p in
                LineMark(x: .value("t", p.t), y: .value("v", p.actual), series: .value("s", "you"))
                    .foregroundStyle(.ocean).interpolationMethod(.catmullRom)
            }
            ForEach(pts) { p in
                LineMark(x: .value("t", p.t), y: .value("v", p.ideal), series: .value("s", "ideal"))
                    .foregroundStyle(.teal.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4])).interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: lo...hi)
        .chartYAxis(.hidden)
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 3)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
        .frame(height: 130)
    }

    private func legend(hasGain: Bool) -> some View {
        HStack(spacing: 12) {
            if hasGain { swatch(.green.opacity(0.5), "Recovered") }
            swatch(.gray.opacity(0.35), "Still lost")
            HStack(spacing: 4) { Capsule().fill(.teal).frame(width: 10, height: 2); Text("Rested night") }
            Spacer()
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func swatch(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 8); Text(t) }
    }

    // MARK: - Shared bits

    private func line(_ icon: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon).font(.caption2).foregroundStyle(tint).frame(width: 14)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func leverChip(napPeak: Int?, evening: Bool) -> some View {
        let (text, icon, tint): (String, String, Color) = {
            if !evening, let napPeak {
                return ("Biggest lever now: a power nap → ~\(napPeak)%", "moon.zzz.fill", .ocean)
            }
            return ("Biggest lever now: protect tonight's sleep — a steady, earlier night lifts tomorrow's whole curve.",
                    "moon.stars.fill", .ocean)
        }()
        return Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.vertical, 6).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(tint)
    }

    // MARK: - Model helpers

    private func samples(actual: AlertnessRhythm, bare: AlertnessRhythm, rested: AlertnessRhythm,
                         from: Date, to: Date) -> [P] {
        guard to > from else { return [] }
        var out: [P] = []
        var t = from
        while t <= to {
            out.append(P(t: t, bare: bare.level(at: t), actual: actual.level(at: t), ideal: rested.level(at: t)))
            t = t.addingTimeInterval(1200)
        }
        return out
    }

    private func napPotential(_ r: AlertnessRhythm, now: Date, dayEnd: Date) -> Double? {
        guard now < dayEnd.addingTimeInterval(-2 * 3600) else { return nil }
        let from = now.addingTimeInterval(NapType.power.targetWakeAfterOnset)
        return r.projectedReadings(napType: .power, napAt: now, from: from, to: dayEnd, step: 1200).map(\.level).max()
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
