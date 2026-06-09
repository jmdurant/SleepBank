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
                header(nowLevel: nowLevel, shortNight: rhythm.isShortNight)
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

    // MARK: - Header

    private func header(nowLevel: Double, shortNight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Today's Alertness").font(.headline)
                Spacer()
                Text("\(Int((nowLevel * 100).rounded()))% now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(shortNight
                 ? "Short night — your curve sits lower today. A nap can lift the afternoon."
                 : "Your predicted rhythm. The dashed line is where a nap now could take you.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                Text("\(Int(d.total.rounded())) min daylight today")
                    .font(.caption.weight(.medium))
                if d.morning >= 1 {
                    Text("· \(Int(d.morning.rounded())) min this morning")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let nudge = daylightNudge(d, isMorning: isMorning) {
                Text(nudge).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func daylightNudge(_ d: DaylightDay, isMorning: Bool) -> String? {
        // Framing per DAYLIGHT_EVIDENCE.md: the honest win is circadian anchoring +
        // better sleep tonight (and a cortisol-mediated morning wake-up), not a big
        // acute alertness jolt. "20 min" is a soft heuristic, not a validated dose.
        if d.morning >= 20 {
            return "☀️ Morning light in — anchors your rhythm and helps you sleep tonight."
        }
        if isMorning {
            return "A morning walk outside anchors your rhythm and helps tonight's sleep."
        }
        return nil
    }

    // MARK: - Model wiring

    private func makeRhythm(now: Date) -> AlertnessRhythm {
        let summary = health.lastNightSleep
        let typical = summary?.averageLast7Days ?? health.sleepAverage7Day
        return AlertnessRhythm.fromSleep(
            wakeTime: summary?.wakeTime,
            sleptHours: summary?.totalHours ?? 0,
            typicalHours: typical,
            naps: napsToday(now: now),
            morningLightDose: AlertnessRhythm.morningLightDose(minutes: health.daylightToday.morning),
            now: now
        )
    }

    /// Today's completed naps that reached sleep, as rhythm discharges.
    private func napsToday(now: Date) -> [AlertnessRhythm.Nap] {
        let cal = Calendar.current
        return store.records.compactMap { r -> AlertnessRhythm.Nap? in
            guard let onset = r.onset, cal.isDate(r.start, inSameDayAs: now) else { return nil }
            let asleep = r.end.timeIntervalSince(onset)
            let fullness = min(asleep / r.type.targetWakeAfterOnset, 1)
            return AlertnessRhythm.Nap(end: r.end, type: r.type, fullness: fullness)
        }
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
