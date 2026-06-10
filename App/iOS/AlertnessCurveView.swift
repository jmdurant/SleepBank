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

    /// The nap start time the user has dragged to. Nil = "right now" (the default
    /// "if you nap now" projection).
    @State private var scrubNapAt: Date?
    /// Which nap the user is exploring on the curve.
    @State private var napType: NapType = .power
    /// Brief "✓ scheduled" feedback after tapping +.
    @State private var scheduledAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let now = context.date
            let rhythm = makeRhythm(now: now)
            let window = curveWindow(wake: rhythm.wakeTime, now: now)
            let baseline = rhythm.readings(from: window.start, to: window.end, step: 1200)
            let nowLevel = rhythm.level(at: now)
            // Draggable hypothetical nap: a valid start time (clamped into the window),
            // and the recovery curve it would produce.
            let napRange = napScrubRange(rhythm: rhythm, now: now, window: window, type: napType)
            let napAt: Date? = napRange.map { clampNap(scrubNapAt ?? now, to: $0) }
            // Start the projection at the nap moment (not the wake time) so the dashed
            // line emanates from the moon marker: flat along the baseline during the
            // nap, then rising as you wake. Finer step for a smooth post-nap rise.
            let projection = napAt.map {
                rhythm.projectedReadings(napType: napType, napAt: $0, from: $0,
                                         to: window.end, step: 300)
            } ?? []
            // The "rested ceiling": where today's curve would sit after a 100 Sleep
            // Score night. Always drawn — when you're already rested it simply hugs
            // your real curve; when you're short it opens a visible gap to close.
            let ideal = AlertnessRhythm(wakeTime: rhythm.wakeTime, sleepDebt: 0.05)
            let idealReadings = ideal.readings(from: window.start, to: window.end, step: 1200)
            // What today's nap/light/movement actually bought you: the elapsed-day gap
            // between your real curve and the same sleep with none of those.
            let gain = gainReadings(rhythm: rhythm, now: now, window: window)
            let yRange = yDomain(baseline: baseline, ideal: idealReadings, projection: projection, nowLevel: nowLevel)
            // The nap as a span on the chart: start (the moon), wake, and its level.
            let nap: (start: Date, wake: Date, level: Double)? = napAt.map {
                ($0, $0.addingTimeInterval(napType.targetWakeAfterOnset), rhythm.level(at: $0))
            }
            // Does this nap steal tonight's sleepiness? (Meaningfully elevated alertness
            // at bedtime — a deep nap's durable tail leaves a small residual even from
            // midday, so the bar is set where it actually impairs sleep onset.)
            let nightCost = napAt.map { nightSleepCost(rhythm: rhythm, napAt: $0, type: napType) } ?? 0
            let napLate = nightCost >= 0.065

            VStack(alignment: .leading, spacing: 10) {
                youAreHere(rhythm: rhythm, now: now, napAt: napAt, napLate: napLate)
                chart(baseline: baseline, projection: projection, ideal: idealReadings,
                      gain: gain, now: now, nowLevel: nowLevel, yRange: yRange,
                      nap: nap, napLate: napLate,
                      setNap: { raw in if let r = napRange { scrubNapAt = clampNap(raw, to: r); scheduledAt = nil } })
                    .frame(height: 170)
                legend(hasProjection: !projection.isEmpty, hasIdeal: true, hasGain: !gain.isEmpty, napLate: napLate)
                if let napAt, !projection.isEmpty {
                    napTypeToggle
                    napScrubRow(rhythm: rhythm, napAt: napAt, projection: projection, napLate: napLate)
                } else if let g = gainNowPct(rhythm: rhythm, now: now), !gain.isEmpty {
                    gainCallout(g, rhythm: rhythm)
                } else if let gap = idealGap(rhythm: rhythm, ideal: ideal, now: now) {
                    idealCallout(gap)
                }
                Divider()
                daylightRow()
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - "You are here"

    /// The emotional centre of the card: where you are right now, *why*, plus a "+"
    /// to schedule a nap at the currently-selected time.
    private func youAreHere(rhythm: AlertnessRhythm, now: Date, napAt: Date?, napLate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Your day · \(AlertnessProvider.phaseLabel(now))").font(.headline)
                Spacer()
                if let napAt { scheduleButton(napAt, napLate: napLate) }
            }
            Text(whyLine(rhythm)).font(.caption).foregroundStyle(.secondary)
            if napAt == nil, let action = morningNudge(rhythm: rhythm, now: now) {
                Label(action.text, systemImage: action.icon)
                    .font(.caption.weight(.medium))
                    .padding(.vertical, 4).padding(.horizontal, 9)
                    .background(action.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(action.tint)
            }
        }
    }

    /// Choose which nap to explore on the curve — power (short) vs cycle (long).
    private var napTypeToggle: some View {
        Picker("Nap type", selection: $napType) {
            Text("Power · 20 min").tag(NapType.power)
            Text("Cycle · 90 min").tag(NapType.cycle)
        }
        .pickerStyle(.segmented)
    }

    /// The "+" (or "✓" right after tapping) that schedules a nap reminder at the
    /// dragged time, for the selected nap type.
    private func scheduleButton(_ napAt: Date, napLate: Bool) -> some View {
        let done = scheduledAt.map { abs($0.timeIntervalSince(napAt)) < 60 } ?? false
        let tint: Color = done ? .green : (napLate ? .orange : .indigo)
        return Button {
            Task {
                if await PlanNotificationService.shared.scheduleNap(at: napAt, type: napType) {
                    scheduledAt = napAt
                }
            }
        } label: {
            Image(systemName: done ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: done)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "Nap reminder scheduled" : "Schedule a nap at this time")
    }

    /// A live readout of the dragged nap: when, the boost it delivers, and — when it's
    /// too late — a warning that it'll cost tonight's sleep.
    private func napScrubRow(rhythm: AlertnessRhythm, napAt: Date,
                             projection: [AlertnessRhythm.Reading], napLate: Bool) -> some View {
        let wake = napAt.addingTimeInterval(napType.targetWakeAfterOnset)
        let peak = projection.max(by: { $0.level < $1.level })
        let boost = peak.map { max(0, Int((($0.level - rhythm.level(at: $0.date)) * 100).rounded())) } ?? 0
        let scheduled = scheduledAt.map { abs($0.timeIntervalSince(napAt)) < 60 } ?? false
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: napLate ? "exclamationmark.triangle.fill" : "moon.zzz.fill")
                .font(.caption2).foregroundStyle(napLate ? .orange : .mint)
            Group {
                if napLate {
                    Text("A nap at **\(napAt, format: .dateTime.hour().minute())** is late — it keeps you alert near bedtime and may delay tonight's sleep. Earlier is better.")
                        .foregroundStyle(.orange)
                } else if scheduled {
                    Text("Reminder set for **\(napAt, format: .dateTime.hour().minute())**. Drag to re-time.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nap at **\(napAt, format: .dateTime.hour().minute())** → up by ~**\(boost)%** through the afternoon (awake \(wake, format: .dateTime.hour().minute())). Tap + to schedule.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
        }
    }

    /// What's shaping your "now" — the inputs converging on the marker.
    private func whyLine(_ rhythm: AlertnessRhythm) -> String {
        var parts = [rhythm.isShortNight ? "Short night" : "Rested"]
        if !rhythm.naps.isEmpty { parts.append("\(rhythm.naps.count) nap\(rhythm.naps.count == 1 ? "" : "s")") }
        if rhythm.morningLightDose > 0.1 { parts.append("morning light ✓") }
        if rhythm.morningActivityDose > 0.1 { parts.append("AM movement ✓") }
        return parts.joined(separator: " · ")
    }

    /// A morning-light nudge while it still helps — shown only when no nap is on the
    /// table (the nap scrubber takes over the action role once one is viable).
    private func morningNudge(rhythm: AlertnessRhythm, now: Date) -> (text: String, icon: String, tint: Color)? {
        if Calendar.current.component(.hour, from: now) < 11, rhythm.morningLightDose < 0.5 {
            return ("Step outside — morning light anchors your day", "sun.max.fill", .orange)
        }
        return nil
    }

    // MARK: - Chart

    private func chart(baseline: [AlertnessRhythm.Reading],
                       projection: [AlertnessRhythm.Reading],
                       ideal: [AlertnessRhythm.Reading],
                       gain: [GainPoint],
                       now: Date, nowLevel: Double,
                       yRange: ClosedRange<Double>,
                       nap: (start: Date, wake: Date, level: Double)?,
                       napLate: Bool,
                       setNap: @escaping (Date) -> Void) -> some View {
        Chart {
            // Base indigo fill under the real curve.
            ForEach(baseline, id: \.date) { r in
                AreaMark(x: .value("Time", r.date), y: .value("Alertness", r.level))
                    .foregroundStyle(.linearGradient(
                        colors: [.indigo.opacity(0.16), .indigo.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom))
            }
            // The nap's duration as a translucent band (start → wake): a thin sliver
            // for a 20-min power nap, a wide block for a 90-min cycle.
            if let n = nap {
                RectangleMark(xStart: .value("Asleep from", n.start),
                              xEnd: .value("Awake", n.wake),
                              yStart: .value("lo", yRange.lowerBound),
                              yEnd: .value("hi", yRange.upperBound))
                    .foregroundStyle((napLate ? Color.orange : .mint).opacity(0.13))
            }
            // The "what your habits added" band: between the no-intervention floor and
            // your real curve, for the part of the day already lived.
            ForEach(gain, id: \.date) { g in
                AreaMark(x: .value("Time", g.date),
                         yStart: .value("Floor", g.bare),
                         yEnd: .value("You", g.actual))
                    .foregroundStyle(.green.opacity(0.22))
            }
            ForEach(gain, id: \.date) { g in
                LineMark(x: .value("Time", g.date), y: .value("Alertness", g.bare),
                         series: .value("Series", "floor"))
                    .foregroundStyle(.green.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .interpolationMethod(.catmullRom)
            }
            // The faint "rested" ceiling reference.
            ForEach(ideal, id: \.date) { r in
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level),
                         series: .value("Series", "ideal"))
                    .foregroundStyle(.teal.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .interpolationMethod(.catmullRom)
            }
            // The real curve, on top.
            ForEach(baseline, id: \.date) { r in
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level),
                         series: .value("Series", "you"))
                    .foregroundStyle(.indigo)
                    .interpolationMethod(.catmullRom)
            }
            ForEach(projection, id: \.date) { r in
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level),
                         series: .value("Series", "nap"))
                    .foregroundStyle(napLate ? .orange : .mint)
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
            // The draggable nap handle — a mint moon sitting on the curve at the
            // chosen nap time.
            if let n = nap {
                PointMark(x: .value("Nap", n.start), y: .value("Alertness", n.level))
                    .foregroundStyle(.white)
                    .symbolSize(180)
                PointMark(x: .value("Nap", n.start), y: .value("Alertness", n.level))
                    .foregroundStyle(napLate ? .orange : .mint)
                    .symbolSize(110)
                    .annotation(position: .top, spacing: 2) {
                        Image(systemName: napLate ? "exclamationmark.triangle.fill" : "moon.zzz.fill")
                            .font(.system(size: 9)).foregroundStyle(napLate ? .orange : .mint)
                    }
            }
        }
        .chartYScale(domain: yRange)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame {
                    let rect = geo[plot]
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x - rect.minX
                                    if let date: Date = proxy.value(atX: x, as: Date.self) {
                                        setNap(date)
                                    }
                                }
                        )
                }
            }
        }
    }

    private func legend(hasProjection: Bool, hasIdeal: Bool, hasGain: Bool, napLate: Bool) -> some View {
        HStack(spacing: 14) {
            label(color: .indigo, text: "You")
            if hasGain { label(color: .green, text: "Your gain") }
            if hasProjection { label(color: napLate ? .orange : .mint, text: napLate ? "Too late" : "If you nap") }
            if hasIdeal { label(color: .teal, text: "Rested ceiling") }
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

    // MARK: - Ideal-curve gap

    /// A point in time with both the real level and the no-intervention "floor."
    struct GainPoint { let date: Date; let bare: Double; let actual: Double }

    private func gainCallout(_ gain: Int, rhythm: AlertnessRhythm) -> some View {
        var did: [String] = []
        if !rhythm.naps.isEmpty { did.append(rhythm.naps.count == 1 ? "your nap" : "your naps") }
        if rhythm.morningLightDose > 0.1 { did.append("morning light") }
        if rhythm.morningActivityDose > 0.1 { did.append("movement") }
        let what = listPhrase(did)
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: "arrow.up.circle.fill").font(.caption2).foregroundStyle(.green)
            Text("\(what) ha\(did.count == 1 ? "s" : "ve") you about **\(gain)% higher** right now than the same night with none of it.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func listPhrase(_ items: [String]) -> String {
        switch items.count {
        case 0:  return "Your habits"
        case 1:  return items[0].prefix(1).capitalized + items[0].dropFirst()
        case 2:  return "\(items[0].prefix(1).capitalized + items[0].dropFirst()) + \(items[1])"
        default: return "\(items[0].prefix(1).capitalized + items[0].dropFirst()) + \(items[1]) + \(items[2])"
        }
    }

    private func idealCallout(_ gap: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "arrow.up.forward").font(.caption2).foregroundStyle(.secondary)
            Text("A fully-rested night would sit about **\(gap)% higher** right now. A nap closes most of that gap; morning light and movement chip away at it too.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Daylight

    /// Apple Watch "Time in Daylight," with the morning window (the circadian-
    /// critical part) called out, plus a gentle nudge. Light anchors Process C —
    /// the curve's height — the natural counterpart to the nap discharging Process
    /// S. (The exact morning target and curve weighting land with the daylight
    /// evidence pass; for now this surfaces the metric and a soft nudge.)
    private func daylightRow() -> some View {
        let d = health.daylightToday
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
                if let nudge = daylightNudge(d, walkMinutes: walk) {
                    Text(nudge).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func daylightNudge(_ d: DaylightDay, walkMinutes: Double) -> String? {
        // Framing per DAYLIGHT_EVIDENCE.md: the honest win is circadian anchoring +
        // better sleep tonight. A morning walk stacks two levers — light (cortisol)
        // and movement (exercise zeitgeber). Soft heuristics, not validated doses.
        if d.morning >= 20 && walkMinutes >= 10 {
            return "☀️🚶 Morning light + movement — both anchor your rhythm and help you sleep tonight."
        }
        if d.morning >= 20 {
            return "☀️ Morning light in — anchors your rhythm and helps you sleep tonight."
        }
        return nil
    }

    // MARK: - Model wiring

    private func makeRhythm(now: Date) -> AlertnessRhythm {
        AlertnessProvider.rhythm(health: health, store: store, now: now)
    }

    /// Tight Y-axis window around the data (the curve rarely uses the full 0…1), with
    /// a little headroom so the lines don't kiss the frame. Eliminates the dead space
    /// above and below the curve.
    private func yDomain(baseline: [AlertnessRhythm.Reading],
                         ideal: [AlertnessRhythm.Reading],
                         projection: [AlertnessRhythm.Reading],
                         nowLevel: Double) -> ClosedRange<Double> {
        let levels = baseline.map(\.level) + ideal.map(\.level) + projection.map(\.level) + [nowLevel]
        let lo = max(0, (levels.min() ?? 0) - 0.06)
        let hi = min(1, (levels.max() ?? 1) + 0.06)
        return lo < hi ? lo...hi : 0...1
    }

    /// Rounded percentage the rested ceiling sits above the actual curve *right now*,
    /// or nil when it's negligible.
    private func idealGap(rhythm: AlertnessRhythm, ideal: AlertnessRhythm, now: Date) -> Int? {
        let gap = ideal.level(at: now) - rhythm.level(at: now)
        let pct = Int((gap * 100).rounded())
        return pct >= 3 ? pct : nil
    }

    /// The counterfactual: the same short night with no nap, light, or movement —
    /// the floor your interventions lifted you off.
    private func bareRhythm(_ rhythm: AlertnessRhythm) -> AlertnessRhythm {
        AlertnessRhythm(wakeTime: rhythm.wakeTime, sleepDebt: rhythm.sleepDebt)
    }

    private func hasInterventions(_ r: AlertnessRhythm) -> Bool {
        !r.naps.isEmpty || r.morningLightDose > 0.1 || r.morningActivityDose > 0.1
    }

    /// The elapsed-day band between the no-intervention floor and your real curve.
    /// Empty when you've done nothing yet, or the lift is too small to bother drawing.
    private func gainReadings(rhythm: AlertnessRhythm, now: Date,
                              window: (start: Date, end: Date)) -> [GainPoint] {
        guard hasInterventions(rhythm) else { return [] }
        let bare = bareRhythm(rhythm)
        let end = min(now, window.end)
        guard end > window.start else { return [] }
        var pts: [GainPoint] = []
        var t = window.start
        while t < end {
            pts.append(GainPoint(date: t, bare: bare.level(at: t), actual: rhythm.level(at: t)))
            t = t.addingTimeInterval(1200)
        }
        pts.append(GainPoint(date: end, bare: bare.level(at: end), actual: rhythm.level(at: end)))
        let maxGain = pts.map { $0.actual - $0.bare }.max() ?? 0
        return maxGain >= 0.015 ? pts : []
    }

    /// How much higher your interventions have you *right now*, in points; nil when negligible.
    private func gainNowPct(rhythm: AlertnessRhythm, now: Date) -> Int? {
        guard hasInterventions(rhythm) else { return nil }
        let gap = rhythm.level(at: now) - bareRhythm(rhythm).level(at: now)
        let pct = Int((gap * 100).rounded())
        return pct >= 2 ? pct : nil
    }

    private func curveWindow(wake: Date, now: Date) -> (start: Date, end: Date) {
        let start = wake
        let end = wake.addingTimeInterval(17 * 3600)   // ~through the evening
        return (start, max(end, now.addingTimeInterval(3600)))
    }

    /// The range of valid nap *start* times: no earlier than now (or just after wake),
    /// and early enough to leave ≥1 h of day to benefit from. Nil when the day's too
    /// far gone to nap usefully.
    private func napScrubRange(rhythm: AlertnessRhythm, now: Date,
                               window: (start: Date, end: Date), type: NapType) -> (earliest: Date, latest: Date)? {
        let napDur = type.targetWakeAfterOnset
        let earliest = max(now, rhythm.wakeTime.addingTimeInterval(1800))
        let latest = window.end.addingTimeInterval(-(napDur + 3600))
        return latest > earliest ? (earliest, latest) : nil
    }

    private func clampNap(_ d: Date, to r: (earliest: Date, latest: Date)) -> Date {
        min(max(d, r.earliest), r.latest)
    }

    /// How much a nap would still have you elevated at bedtime (~16 h after waking) —
    /// i.e. how much it steals tonight's sleepiness. The display-scale gap between the
    /// napped curve and baseline at bedtime.
    private func nightSleepCost(rhythm: AlertnessRhythm, napAt: Date, type: NapType) -> Double {
        let bedtime = rhythm.wakeTime.addingTimeInterval(16 * 3600)
        return rhythm.level(at: bedtime, withNapAt: napAt, type: type) - rhythm.level(at: bedtime)
    }
}
