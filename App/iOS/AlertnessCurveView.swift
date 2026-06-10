//
//  AlertnessCurveView.swift
//  SleepBank
//
//  The day's predicted alertness rhythm (two-process model) — a non-linear curve
//  with the late-morning rise, the post-lunch dip, the evening "second wind," and
//  the night plunge. Last night's sleep sets where the whole curve sits (a short
//  night drops it); a "you are here" marker shows the moment, and a dashed branch
//  shows where a nap *now* could lift the rest of your day. Honest companion to
//  the energy ring: the ring is right-now, this is the whole arc.
//

import SwiftUI
import Charts
import SleepBankCore

struct AlertnessCurveView: View {
    var health = HealthKitService.shared
    var store = NapDecisionStore.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let now = context.date
            let rhythm = makeRhythm(now: now)
            let window = curveWindow(wake: rhythm.wakeTime, now: now)
            let baseline = rhythm.readings(from: window.start, to: window.end, step: 1200)
            let nowLevel = rhythm.level(at: now)
            let projection = projectionReadings(rhythm: rhythm, now: now, window: window)

            VStack(alignment: .leading, spacing: 10) {
                youAreHere(rhythm: rhythm, now: now, nowLevel: nowLevel, projection: projection)
                chart(baseline: baseline, projection: projection, now: now, nowLevel: nowLevel)
                    .frame(height: 170)
                legend(hasProjection: !projection.isEmpty)
                Divider()
                daylightRow(now: now)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - "You are here"

    /// The emotional centre of the card: where you are right now, *why* (last
    /// night's sleep + today's naps/light/movement all converge on this point), and
    /// the single most-relevant next move for the moment.
    private func youAreHere(rhythm: AlertnessRhythm, now: Date,
                            nowLevel: Double, projection: [AlertnessRhythm.Reading]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's Alertness").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(pct(nowLevel))%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 0) {
                    Text("you are here").font(.caption2).foregroundStyle(.secondary)
                    Text(phaseLabel(now)).font(.subheadline.weight(.semibold))
                }
                Spacer()
            }
            Text(whyLine(rhythm)).font(.caption).foregroundStyle(.secondary)
            if let action = actionSuggestion(rhythm: rhythm, now: now, projection: projection) {
                Label(action.text, systemImage: action.icon)
                    .font(.caption.weight(.medium))
                    .padding(.vertical, 4).padding(.horizontal, 9)
                    .background(action.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(action.tint)
            }
        }
    }

    private func pct(_ level: Double) -> Int { AlertnessProvider.pct(level) }
    private func phaseLabel(_ now: Date) -> String { AlertnessProvider.phaseLabel(now) }

    /// What's shaping your "now" — the inputs converging on the marker.
    private func whyLine(_ rhythm: AlertnessRhythm) -> String {
        var parts = [rhythm.isShortNight ? "Short night" : "Rested"]
        if !rhythm.naps.isEmpty { parts.append("\(rhythm.naps.count) nap\(rhythm.naps.count == 1 ? "" : "s")") }
        if rhythm.morningLightDose > 0.1 { parts.append("morning light ✓") }
        if rhythm.morningActivityDose > 0.1 { parts.append("AM movement ✓") }
        return parts.joined(separator: " · ")
    }

    /// The single most-relevant move for the moment: a nap when it would meaningfully
    /// lift the rest of the day; otherwise a morning-light nudge while it still helps.
    private func actionSuggestion(rhythm: AlertnessRhythm, now: Date,
                                  projection: [AlertnessRhythm.Reading]) -> (text: String, icon: String, tint: Color)? {
        if let peak = projection.max(by: { $0.level < $1.level }) {
            let gain = peak.level - rhythm.level(at: peak.date)
            if gain >= 0.03 {
                return ("A power nap now → lifts you to ~\(pct(peak.level))%", "moon.zzz.fill", .indigo)
            }
        }
        if Calendar.current.component(.hour, from: now) < 11, rhythm.morningLightDose < 0.5 {
            return ("Step outside — morning light anchors your day", "sun.max.fill", .orange)
        }
        return nil
    }

    // MARK: - Chart

    private func chart(baseline: [AlertnessRhythm.Reading],
                       projection: [AlertnessRhythm.Reading],
                       now: Date, nowLevel: Double) -> some View {
        Chart {
            ForEach(baseline, id: \.date) { r in
                AreaMark(x: .value("Time", r.date), y: .value("Alertness", r.level))
                    .foregroundStyle(.linearGradient(
                        colors: [.indigo.opacity(0.28), .indigo.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level))
                    .foregroundStyle(.indigo)
                    .interpolationMethod(.catmullRom)
            }
            ForEach(projection, id: \.date) { r in
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level),
                         series: .value("Series", "nap"))
                    .foregroundStyle(.mint)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .interpolationMethod(.catmullRom)
            }
            RuleMark(x: .value("Now", now))
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("Now", now), y: .value("Alertness", nowLevel))
                .foregroundStyle(.white)
                .symbolSize(120)
            PointMark(x: .value("Now", now), y: .value("Alertness", nowLevel))
                .foregroundStyle(.indigo)
                .symbolSize(60)
        }
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }

    private func legend(hasProjection: Bool) -> some View {
        HStack(spacing: 14) {
            label(color: .indigo, text: "Predicted")
            if hasProjection { label(color: .mint, text: "If you nap now") }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func label(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }

    // MARK: - Daylight

    /// Apple Watch "Time in Daylight," with the morning window (the circadian-
    /// critical part) called out, plus a gentle nudge. Light anchors Process C —
    /// the curve's height — the natural counterpart to the nap discharging Process
    /// S. (The exact morning target and curve weighting land with the daylight
    /// evidence pass; for now this surfaces the metric and a soft nudge.)
    private func daylightRow(now: Date) -> some View {
        let d = health.daylightToday
        let hour = Calendar.current.component(.hour, from: now)
        let isMorning = hour < 11
        let streak = health.morningLightStreak
        let walk = health.morningActivityMinutes
        return NavigationLink(value: HomeRoute.daylight) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                    Text("\(Int(d.total.rounded())) min daylight today")
                        .font(.caption.weight(.medium)).foregroundStyle(.primary)
                    if d.morning >= 1 {
                        Text("· \(Int(d.morning.rounded())) min AM")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if walk >= 1 {
                        Text("· 🚶 \(Int(walk.rounded())) min AM")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if streak > 0 {
                        Text("🌅 \(streak)").font(.caption.weight(.semibold)).foregroundStyle(.primary)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                if let nudge = daylightNudge(d, walkMinutes: walk, isMorning: isMorning) {
                    Text(nudge).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func daylightNudge(_ d: DaylightDay, walkMinutes: Double, isMorning: Bool) -> String? {
        // Framing per DAYLIGHT_EVIDENCE.md: the honest win is circadian anchoring +
        // better sleep tonight. A morning walk stacks two levers — light (cortisol)
        // and movement (exercise zeitgeber). Soft heuristics, not validated doses.
        if d.morning >= 20 && walkMinutes >= 10 {
            return "☀️🚶 Morning light + movement — both anchor your rhythm and help you sleep tonight."
        }
        if d.morning >= 20 {
            return "☀️ Morning light in — anchors your rhythm and helps you sleep tonight."
        }
        if isMorning {
            return "A morning walk outside stacks light + movement — anchors your rhythm for tonight's sleep."
        }
        return nil
    }

    // MARK: - Model wiring

    private func makeRhythm(now: Date) -> AlertnessRhythm {
        AlertnessProvider.rhythm(health: health, store: store, now: now)
    }

    private func curveWindow(wake: Date, now: Date) -> (start: Date, end: Date) {
        let start = wake
        let end = wake.addingTimeInterval(17 * 3600)   // ~through the evening
        return (start, max(end, now.addingTimeInterval(3600)))
    }

    /// The dashed "where you could be" segment — only when there's still useful day
    /// left to nap into.
    private func projectionReadings(rhythm: AlertnessRhythm, now: Date,
                                    window: (start: Date, end: Date)) -> [AlertnessRhythm.Reading] {
        let wakeFromNap = now.addingTimeInterval(NapType.power.targetWakeAfterOnset)
        guard wakeFromNap < window.end.addingTimeInterval(-3600),
              now > rhythm.wakeTime.addingTimeInterval(1800) else { return [] }
        return rhythm.projectedReadings(napType: .power, napAt: now,
                                        from: wakeFromNap, to: window.end, step: 1200)
    }
}
