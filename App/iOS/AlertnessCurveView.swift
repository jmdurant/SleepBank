//
//  AlertnessCurveView.swift
//  SleepBank
//
//  The day's predicted alertness rhythm (two-process model) — a non-linear curve
//  with the late-morning rise, the post-lunch dip, the evening "second wind," and
//  the night plunge. Last night's sleep sets where the whole curve sits. On top of
//  that you can *plan*: drag a nap, a walk, or a workout along the curve and watch
//  the combined "your plan" line lift in real time — then schedule it. Late or
//  intense additions turn orange (they'd cost tonight's sleep). Honest companion to
//  the energy ring: the ring is right-now, this is the whole arc.
//

import SwiftUI
import Charts
import SleepBankCore

struct AlertnessCurveView: View {
    var health = HealthKitService.shared
    var store = NapDecisionStore.shared

    /// Which intervention the drag/readout currently edits.
    enum Intervention: String, CaseIterable, Identifiable {
        case nap, walk, workout
        var id: String { rawValue }
        var label: String { self == .nap ? "Nap" : (self == .walk ? "Walk" : "Workout") }
        var icon: String {
            switch self {
            case .nap:     return "moon.zzz.fill"
            case .walk:    return "figure.walk"
            case .workout: return "figure.run"
            }
        }
        var tint: Color {
            switch self {
            case .nap:     return .mint
            case .walk:    return .orange
            case .workout: return .pink
            }
        }
    }

    /// A planned activity bout's editable state.
    struct ActivityPlan {
        var on = false
        var at: Date?
        var minutes: Double
        var outdoors: Bool
    }

    @State private var selected: Intervention = .nap
    @State private var napOn = true
    @State private var napType: NapType = .power
    @State private var scrubNapAt: Date?
    @State private var walk = ActivityPlan(minutes: 30, outdoors: true)
    @State private var workout = ActivityPlan(minutes: 60, outdoors: false)
    /// The intervention + time most recently scheduled, for ✓ feedback.
    @State private var scheduledKey: String?
    @State private var editing = false
    @State private var isDragging = false

    // MARK: - Body

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let now = context.date
            let rhythm = makeRhythm(now: now)
            let window = curveWindow(wake: rhythm.wakeTime, now: now)
            let baseline = rhythm.readings(from: window.start, to: window.end, step: 1200)
            let nowLevel = rhythm.level(at: now)
            let ideal = AlertnessRhythm(wakeTime: rhythm.wakeTime, sleepDebt: 0.05)
            let idealReadings = ideal.readings(from: window.start, to: window.end, step: 1200)
            let gain = gainReadings(rhythm: rhythm, now: now, window: window)

            // Resolve the plan in order (nap → walk → workout), each auto-placed into the
            // first free slot so a freshly-added one spreads out instead of stacking.
            let napRange = napOn ? napScrubRange(rhythm: rhythm, now: now, window: window, type: napType) : nil
            let napAt: Date? = napRange.map { clampNap(scrubNapAt ?? now, to: $0) }
            let nap: AlertnessRhythm.Nap? = napAt.map {
                .init(end: $0.addingTimeInterval(napType.targetWakeAfterOnset), type: napType, fullness: 1)
            }
            let napIv = napAt.map { ($0, $0.addingTimeInterval(napType.targetWakeAfterOnset)) }
            let walkRange = activityRange(plan: walk, now: now, window: window)
            let walkAct = resolved(walk, .walk, range: walkRange, now: now,
                                   obstacles: [napIv].compactMap { $0 })
            let walkIv = walkAct.map { ($0.start, $0.start.addingTimeInterval($0.duration)) }
            let workoutRange = activityRange(plan: workout, now: now, window: window)
            let workoutAct = resolved(workout, .workout, range: workoutRange, now: now,
                                      obstacles: [napIv, walkIv].compactMap { $0 })
            let workoutIv = workoutAct.map { ($0.start, $0.start.addingTimeInterval($0.duration)) }
            let activities = [walkAct, workoutAct].compactMap { $0 }

            // The combined "your plan" curve, branching off where the first item starts.
            let starts = [napAt, walkAct?.start, workoutAct?.start].compactMap { $0 }
            let planStart = starts.min()
            let projection: [AlertnessRhythm.Reading] = planStart.map {
                rhythm.planReadings(nap: nap, activities: activities, from: $0, to: window.end, step: 300)
            } ?? []

            let markers = buildMarkers(rhythm: rhythm, now: now, nap: nap, napAt: napAt,
                                       activities: activities)
            let bands = buildBands(napAt: napAt, activities: activities, markers: markers)
            let yRange = yDomain(baseline: baseline, ideal: idealReadings, projection: projection, nowLevel: nowLevel)
            let onDrag = makeDragHandler(napRange: napRange, walkRange: walkRange, workoutRange: workoutRange,
                                         napIv: napIv, walkIv: walkIv, workoutIv: workoutIv, markers: markers)
            // The peak the draft plan reaches — drives the home battery's live preview.
            let planActive = nap != nil || !activities.isEmpty
            let peak = planActive ? projection.max(by: { $0.level < $1.level }) : nil

            VStack(alignment: .leading, spacing: 10) {
                header(rhythm: rhythm, now: now, markers: markers)
                chart(baseline: baseline, projection: projection, ideal: idealReadings, gain: gain,
                      now: now, nowLevel: nowLevel, yRange: yRange, markers: markers, bands: bands,
                      onDrag: onDrag)
                    .frame(height: 170)
                legend(hasPlan: !projection.isEmpty, planLate: markers.contains { $0.late })
                interventionPicker
                if selected == .nap, napOn { napTypeToggle }
                selectedReadout(rhythm: rhythm, now: now, markers: markers,
                                napAt: napAt, projection: projection)
                Divider()
                daylightRow()
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .sheet(isPresented: $editing) { activityEditor }
            .onAppear { PlanPreview.shared.level = peak?.level; PlanPreview.shared.peakTime = peak?.date }
            .onChange(of: peak?.level) { _, lvl in
                PlanPreview.shared.level = lvl
                PlanPreview.shared.peakTime = peak?.date
            }
            .onDisappear { PlanPreview.shared.level = nil; PlanPreview.shared.peakTime = nil }
        }
    }

    // MARK: - Header

    private func header(rhythm: AlertnessRhythm, now: Date, markers: [Marker]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Your day · \(AlertnessProvider.phaseLabel(now))").font(.headline)
                Spacer()
                if let m = markers.first(where: { $0.kind == selected }) {
                    HStack(spacing: 4) {
                        Image(systemName: m.late ? "exclamationmark.triangle.fill" : m.kind.icon)
                            .font(.caption2)
                        Text(m.start, format: .dateTime.hour().minute())
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(m.late ? .orange : m.kind.tint)
                    scheduleButton(m)
                }
            }
            Text(whyLine(rhythm)).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The "+" / "✓" that schedules the selected intervention at its current time.
    private func scheduleButton(_ m: Marker) -> some View {
        let done = scheduledKey == key(m.kind, m.start)
        let tint: Color = done ? .green : (m.late ? .orange : m.kind.tint)
        return Button {
            Task {
                let ok: Bool
                switch m.kind {
                case .nap:
                    ok = await PlanNotificationService.shared.scheduleNap(at: m.start, type: napType)
                case .walk, .workout:
                    ok = await PlanNotificationService.shared.scheduleActivity(
                        at: m.start, title: m.kind.label, outdoors: outdoors(for: m.kind))
                }
                if ok { scheduledKey = key(m.kind, m.start) }
            }
        } label: {
            Image(systemName: done ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.title3).foregroundStyle(tint)
                .symbolEffect(.bounce, value: done)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "Scheduled" : "Schedule \(m.kind.label) at this time")
    }

    // MARK: - Intervention picker + editors

    private var interventionPicker: some View {
        HStack(spacing: 8) {
            ForEach(Intervention.allCases) { kind in
                let on = isOn(kind)
                Button {
                    if selected == kind {
                        toggle(kind)   // tapping the focused chip removes it from the plan
                        if !isOn(kind) {   // …and focus jumps to one that's still on the curve
                            selected = Intervention.allCases.first(where: isOn) ?? kind
                        }
                    } else {
                        selected = kind            // focus it
                        if !isOn(kind) { toggle(kind) }   // adding it if it wasn't on
                    }
                    scheduledKey = nil
                } label: {
                    let focused = selected == kind && on   // only an *active* chip shows as focused
                    HStack(spacing: 5) {
                        Image(systemName: kind.icon).font(.caption2)
                        Text(kind.label).font(.caption.weight(.medium))
                        if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background((focused ? kind.tint.opacity(0.22) : Color.secondary.opacity(0.12)),
                                in: Capsule())
                    .foregroundStyle(focused ? kind.tint : .secondary)
                    .overlay(Capsule().stroke(focused ? kind.tint : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var napTypeToggle: some View {
        Picker("Nap type", selection: $napType) {
            Text("Power · 20 min").tag(NapType.power)
            Text("Cycle · 90 min").tag(NapType.cycle)
        }
        .pickerStyle(.segmented)
    }

    /// Hold-to-edit sheet for the selected activity: duration + indoors/outdoors.
    private var activityEditor: some View {
        let isWalk = selected == .walk
        return NavigationStack {
            Form {
                Section(selected.label) {
                    Stepper(value: isWalk ? $walk.minutes : $workout.minutes, in: 10...120, step: 5) {
                        Text("\(Int(isWalk ? walk.minutes : workout.minutes)) min").monospacedDigit()
                    }
                    Picker("Where", selection: isWalk ? $walk.outdoors : $workout.outdoors) {
                        Text("Outside ☀️").tag(true)
                        Text("Inside").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text((isWalk ? walk.outdoors : workout.outdoors)
                         ? "Outside adds daylight — anchors your rhythm and helps you sleep tonight."
                         : "Indoors gives the movement boost without the light/anchoring benefit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit \(selected.label)")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } } }
        }
        .presentationDetents([.height(260)])
    }

    // MARK: - Selected readout

    @ViewBuilder
    private func selectedReadout(rhythm: AlertnessRhythm, now: Date, markers: [Marker],
                                 napAt: Date?, projection: [AlertnessRhythm.Reading]) -> some View {
        if let m = markers.first(where: { $0.kind == selected }) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: m.late ? "exclamationmark.triangle.fill" : m.kind.icon)
                    .font(.caption2).foregroundStyle(m.late ? .orange : m.kind.tint)
                Text(readoutText(m, rhythm: rhythm, projection: projection))
                    .font(.caption2).foregroundStyle(m.late ? .orange : .secondary)
                if selected != .nap {
                    Spacer()
                    Button { editing = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.caption2)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Edit duration and location")
                }
            }
        } else if let g = gainNowPct(rhythm: rhythm, now: now), hasInterventions(rhythm) {
            gainCallout(g, rhythm: rhythm)
        } else if let gap = idealGap(rhythm: rhythm, now: now) {
            idealCallout(gap)
        }
    }

    private func readoutText(_ m: Marker, rhythm: AlertnessRhythm,
                             projection: [AlertnessRhythm.Reading]) -> LocalizedStringKey {
        let t = m.start.formatted(.dateTime.hour().minute())
        if m.kind == .nap {
            if m.late {
                return "A nap at **\(t)** is late — it keeps you alert near bedtime and may delay tonight's sleep. Earlier is better."
            }
            let boost = peakBoost(projection: projection, rhythm: rhythm)
            return "Nap at **\(t)** → up by ~**\(boost)%** through the afternoon. Tap + to schedule."
        }
        // Activity
        let what = m.kind.label.lowercased()
        if m.late {
            return m.lightLate
                ? "A \(what) outside at **\(t)** is in bright evening light — this close to bed it can delay your sleep. Earlier, or after dark, is kinder to your night."
                : "A \(what) at **\(t)** is late — the arousal lingers and may delay tonight's sleep."
        }
        let morning = Calendar.current.component(.hour, from: m.start) < 11
        if outdoors(for: m.kind) && morning {
            return "A \(what) outside at **\(t)** → a lift now, **plus** it anchors your rhythm and helps you sleep tonight. Tap + to schedule."
        }
        if outdoors(for: m.kind) {
            return "A \(what) outside at **\(t)** → a modest lift, plus daylight to steady your rhythm. Tap + to schedule."
        }
        return "A \(what) at **\(t)** → a modest, ~1–2 h lift. Tap + to schedule."
    }

    private func peakBoost(projection: [AlertnessRhythm.Reading], rhythm: AlertnessRhythm) -> Int {
        guard let peak = projection.max(by: { $0.level < $1.level }) else { return 0 }
        return max(0, Int(((peak.level - rhythm.level(at: peak.date)) * 100).rounded()))
    }

    private func whyLine(_ rhythm: AlertnessRhythm) -> String {
        var parts = [rhythm.isShortNight ? "Short night" : "Rested"]
        if !rhythm.naps.isEmpty { parts.append("\(rhythm.naps.count) nap\(rhythm.naps.count == 1 ? "" : "s")") }
        if rhythm.morningLightDose > 0.1 { parts.append("morning light ✓") }
        if rhythm.morningActivityDose > 0.1 { parts.append("AM movement ✓") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Chart

    /// A point on the plan curve the user can drag.
    struct Marker: Identifiable {
        let kind: Intervention
        let start: Date
        let level: Double
        let late: Bool
        let lightLate: Bool   // late specifically because of bright evening light (outdoors, before sunset)
        var id: String { kind.rawValue }
    }
    /// A shaded duration span (nap or activity bout).
    struct Band: Identifiable { let id: String; let start: Date; let end: Date; let late: Bool }
    struct GainPoint { let date: Date; let bare: Double; let actual: Double }

    private func chart(baseline: [AlertnessRhythm.Reading],
                       projection: [AlertnessRhythm.Reading],
                       ideal: [AlertnessRhythm.Reading],
                       gain: [GainPoint],
                       now: Date, nowLevel: Double, yRange: ClosedRange<Double>,
                       markers: [Marker], bands: [Band],
                       onDrag: @escaping (Date, Bool) -> Void) -> some View {
        Chart {
            ForEach(baseline, id: \.date) { r in
                AreaMark(x: .value("Time", r.date), y: .value("Alertness", r.level))
                    .foregroundStyle(.linearGradient(
                        colors: [.indigo.opacity(0.16), .indigo.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom))
            }
            ForEach(bands) { b in
                RectangleMark(xStart: .value("From", b.start), xEnd: .value("To", b.end),
                              yStart: .value("lo", yRange.lowerBound), yEnd: .value("hi", yRange.upperBound))
                    .foregroundStyle((b.late ? Color.orange : .mint).opacity(0.10))
            }
            ForEach(gain, id: \.date) { g in
                AreaMark(x: .value("Time", g.date),
                         yStart: .value("Floor", g.bare), yEnd: .value("You", g.actual))
                    .foregroundStyle(.green.opacity(0.22))
            }
            ForEach(gain, id: \.date) { g in
                LineMark(x: .value("Time", g.date), y: .value("Alertness", g.bare),
                         series: .value("S", "floor"))
                    .foregroundStyle(.green.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(ideal, id: \.date) { r in
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level),
                         series: .value("S", "ideal"))
                    .foregroundStyle(.teal.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(baseline, id: \.date) { r in
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level),
                         series: .value("S", "you"))
                    .foregroundStyle(.indigo)
                    .interpolationMethod(.catmullRom)
            }
            let planLate = markers.contains { $0.late }
            ForEach(projection, id: \.date) { r in
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level),
                         series: .value("S", "plan"))
                    .foregroundStyle(planLate ? .orange : .mint)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .interpolationMethod(.catmullRom)
            }
            RuleMark(x: .value("Now", now))
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("Now", now), y: .value("Alertness", nowLevel))
                .foregroundStyle(.white).symbolSize(120)
            PointMark(x: .value("Now", now), y: .value("Alertness", nowLevel))
                .foregroundStyle(.indigo).symbolSize(60)
            ForEach(markers) { m in
                PointMark(x: .value("At", m.start), y: .value("Alertness", m.level))
                    .foregroundStyle(.white)
                    .symbolSize(m.kind == selected ? 200 : 150)
                PointMark(x: .value("At", m.start), y: .value("Alertness", m.level))
                    .foregroundStyle(m.late ? .orange : m.kind.tint)
                    .symbolSize(m.kind == selected ? 120 : 80)
                    .annotation(position: .top, spacing: 2) {
                        Image(systemName: m.late ? "exclamationmark.triangle.fill" : m.kind.icon)
                            .font(.system(size: 9)).foregroundStyle(m.late ? .orange : m.kind.tint)
                    }
            }
        }
        .chartYScale(domain: yRange)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine(); AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame {
                    let rect = geo[plot]
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let x = v.location.x - rect.minX
                                if let date: Date = proxy.value(atX: x, as: Date.self) {
                                    onDrag(date, !isDragging)   // first touch grabs the nearest marker
                                    isDragging = true
                                }
                            }
                            .onEnded { _ in isDragging = false })
                        .onLongPressGesture { if selected != .nap { editing = true } }
                }
            }
        }
    }

    private func legend(hasPlan: Bool, planLate: Bool) -> some View {
        HStack(spacing: 14) {
            label(color: .indigo, text: "You")
            if hasPlan { label(color: planLate ? .orange : .mint, text: planLate ? "Too late" : "Your plan") }
            label(color: .teal, text: "Rested ceiling")
            Spacer()
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func label(color: Color, text: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 7, height: 7); Text(text) }
    }

    // MARK: - Plan assembly

    private func buildMarkers(rhythm: AlertnessRhythm, now: Date, nap: AlertnessRhythm.Nap?,
                              napAt: Date?, activities: [AlertnessRhythm.Activity]) -> [Marker] {
        let bedtime = rhythm.wakeTime.addingTimeInterval(16 * 3600)
        let sunset = localSunset(now: now)
        let preBed = bedtime.addingTimeInterval(-3 * 3600)
        var out: [Marker] = []
        if let napAt {
            let lvl = rhythm.level(at: napAt, nap: nap, activities: activities)
            let cost = rhythm.level(at: bedtime, nap: nap, activities: activities)
                     - rhythm.level(at: bedtime, nap: nil, activities: activities)
            out.append(Marker(kind: .nap, start: napAt, level: lvl, late: cost >= 0.065, lightLate: false))
        }
        for a in activities {
            let lvl = rhythm.level(at: a.start, nap: nap, activities: activities)
            let costAtBed = rhythm.level(at: bedtime, nap: nap, activities: [a])
                          - rhythm.level(at: bedtime, nap: nap, activities: [])
            // Bright-light caution only when it's *actually* light out — an outdoor
            // bout before sunset and within ~3 h of bed. After dark it's just movement.
            let lightLate = a.outdoors && a.start < sunset && a.start >= preBed
            let late = costAtBed >= 0.035 || lightLate
            out.append(Marker(kind: a.intensity == .walk ? .walk : .workout,
                              start: a.start, level: lvl, late: late, lightLate: lightLate))
        }
        return out
    }

    private func buildBands(napAt: Date?, activities: [AlertnessRhythm.Activity], markers: [Marker]) -> [Band] {
        var out: [Band] = []
        if let napAt {
            let late = markers.first { $0.kind == .nap }?.late ?? false
            out.append(Band(id: "nap", start: napAt,
                            end: napAt.addingTimeInterval(napType.targetWakeAfterOnset), late: late))
        }
        for a in activities {
            let kind: Intervention = a.intensity == .walk ? .walk : .workout
            let late = markers.first { $0.kind == kind }?.late ?? false
            out.append(Band(id: kind.rawValue, start: a.start,
                            end: a.start.addingTimeInterval(a.duration), late: late))
        }
        return out
    }

    private func resolved(_ plan: ActivityPlan, _ intensity: AlertnessRhythm.Activity.Intensity,
                          range: (earliest: Date, latest: Date)?, now: Date,
                          obstacles: [(Date, Date)]) -> AlertnessRhythm.Activity? {
        guard plan.on, let range else { return nil }
        // A user-set time is honoured; an unplaced one drops into the first free slot.
        let at = plan.at.map { min(max($0, range.earliest), range.latest) }
                 ?? firstFreeSlot(range: range, dur: plan.minutes * 60, obstacles: obstacles)
        return AlertnessRhythm.Activity(id: intensity.rawValue, intensity: intensity,
                                        outdoors: plan.outdoors, start: at, duration: plan.minutes * 60)
    }

    /// The earliest start at-or-after `now` whose span clears every obstacle, hopping
    /// past each occupied bout in turn. Falls back to the range end if the day's full.
    private func firstFreeSlot(range: (earliest: Date, latest: Date), dur: TimeInterval,
                               obstacles: [(Date, Date)]) -> Date {
        var t = range.earliest
        for ob in obstacles.sorted(by: { $0.0 < $1.0 }) where t < ob.1 && t.addingTimeInterval(dur) > ob.0 {
            t = ob.1
        }
        return min(t, range.latest)
    }

    private func makeDragHandler(napRange: (earliest: Date, latest: Date)?,
                                 walkRange: (earliest: Date, latest: Date)?,
                                 workoutRange: (earliest: Date, latest: Date)?,
                                 napIv: (Date, Date)?, walkIv: (Date, Date)?,
                                 workoutIv: (Date, Date)?, markers: [Marker]) -> (Date, Bool) -> Void {
        { raw, isFirstTouch in
            // First touch of a drag grabs whichever marker is nearest — so tapping the
            // walk's icon takes control of the walk, not whatever was selected before.
            if isFirstTouch, let near = nearestMarker(to: raw, markers: markers) {
                selected = near.kind
                scheduledKey = nil
            }
            switch selected {
            case .nap:
                if let r = napRange {
                    scrubNapAt = snap(raw, dur: napType.targetWakeAfterOnset, range: r,
                                      obstacles: [walkIv, workoutIv].compactMap { $0 })
                }
            case .walk:
                if let r = walkRange {
                    walk.at = snap(raw, dur: walk.minutes * 60, range: r,
                                   obstacles: [napIv, workoutIv].compactMap { $0 })
                }
            case .workout:
                if let r = workoutRange {
                    workout.at = snap(raw, dur: workout.minutes * 60, range: r,
                                      obstacles: [napIv, walkIv].compactMap { $0 })
                }
            }
            scheduledKey = nil
        }
    }

    /// The active marker nearest a touch point in time, within a grab radius.
    private func nearestMarker(to date: Date, markers: [Marker]) -> Marker? {
        markers.filter { abs($0.start.timeIntervalSince(date)) <= 35 * 60 }
               .min { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
    }

    /// Clamp a dragged start into range AND out of every occupied span — snapping to
    /// just before or just after whichever obstacle it hits (the side nearer the drag),
    /// so a nap, walk, and workout can't overlap in time.
    private func snap(_ raw: Date, dur: TimeInterval, range: (earliest: Date, latest: Date),
                      obstacles: [(Date, Date)]) -> Date {
        var start = min(max(raw, range.earliest), range.latest)
        for _ in 0..<6 {
            guard let ob = obstacles.first(where: { start < $0.1 && start.addingTimeInterval(dur) > $0.0 })
            else { break }
            let before = ob.0.addingTimeInterval(-dur)
            let after = ob.1
            let beforeOK = before >= range.earliest, afterOK = after <= range.latest
            if beforeOK && afterOK {
                start = abs(before.timeIntervalSince(raw)) <= abs(after.timeIntervalSince(raw)) ? before : after
            } else if beforeOK { start = before }
            else if afterOK { start = after }
            else { break }
        }
        return min(max(start, range.earliest), range.latest)
    }

    // MARK: - Small helpers

    private func isOn(_ kind: Intervention) -> Bool {
        switch kind { case .nap: return napOn; case .walk: return walk.on; case .workout: return workout.on }
    }
    private func toggle(_ kind: Intervention) {
        switch kind { case .nap: napOn.toggle(); case .walk: walk.on.toggle(); case .workout: workout.on.toggle() }
    }
    private func outdoors(for kind: Intervention) -> Bool {
        kind == .walk ? walk.outdoors : workout.outdoors
    }
    private func key(_ kind: Intervention, _ date: Date) -> String {
        "\(kind.rawValue)-\(Int(date.timeIntervalSinceReferenceDate / 60))"
    }

    // MARK: - Callouts

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
            Text("A fully-rested night would sit about **\(gap)% higher** right now. Add a nap, walk, or workout to close the gap.")
                .font(.caption2).foregroundStyle(.secondary)
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
                    Text("\(Int(d.total.rounded())) min daylight today")
                        .font(.caption.weight(.medium)).foregroundStyle(.primary)
                    if d.morning >= 1 {
                        Text("· \(Int(d.morning.rounded())) min AM").font(.caption).foregroundStyle(.secondary)
                    }
                    if walkMin >= 1 {
                        Text("· 🚶 \(Int(walkMin.rounded())) min AM").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if streak > 0 {
                        Text("🌅 \(streak)").font(.caption.weight(.semibold)).foregroundStyle(.primary)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                if let nudge = daylightNudge(d, walkMinutes: walkMin) {
                    Text(nudge).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func daylightNudge(_ d: DaylightDay, walkMinutes: Double) -> String? {
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

    /// Local sunset from the user's coarse location; a conservative ~7:30 PM fallback
    /// when location isn't available (still well before a typical late-evening walk).
    private func localSunset(now: Date) -> Date {
        LocationService.shared.solarToday(now)?.sunset
            ?? Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: now) ?? now
    }

    private func yDomain(baseline: [AlertnessRhythm.Reading], ideal: [AlertnessRhythm.Reading],
                         projection: [AlertnessRhythm.Reading], nowLevel: Double) -> ClosedRange<Double> {
        let levels = baseline.map(\.level) + ideal.map(\.level) + projection.map(\.level) + [nowLevel]
        let lo = max(0, (levels.min() ?? 0) - 0.06)
        let hi = min(1, (levels.max() ?? 1) + 0.06)
        return lo < hi ? lo...hi : 0...1
    }

    private func idealGap(rhythm: AlertnessRhythm, now: Date) -> Int? {
        let ideal = AlertnessRhythm(wakeTime: rhythm.wakeTime, sleepDebt: 0.05)
        let pct = Int(((ideal.level(at: now) - rhythm.level(at: now)) * 100).rounded())
        return pct >= 3 ? pct : nil
    }

    private func bareRhythm(_ rhythm: AlertnessRhythm) -> AlertnessRhythm {
        AlertnessRhythm(wakeTime: rhythm.wakeTime, sleepDebt: rhythm.sleepDebt)
    }
    private func hasInterventions(_ r: AlertnessRhythm) -> Bool {
        !r.naps.isEmpty || r.morningLightDose > 0.1 || r.morningActivityDose > 0.1
    }
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
        return (pts.map { $0.actual - $0.bare }.max() ?? 0) >= 0.015 ? pts : []
    }
    private func gainNowPct(rhythm: AlertnessRhythm, now: Date) -> Int? {
        guard hasInterventions(rhythm) else { return nil }
        let pct = Int(((rhythm.level(at: now) - bareRhythm(rhythm).level(at: now)) * 100).rounded())
        return pct >= 2 ? pct : nil
    }

    private func curveWindow(wake: Date, now: Date) -> (start: Date, end: Date) {
        (wake, max(wake.addingTimeInterval(17 * 3600), now.addingTimeInterval(3600)))
    }

    private func napScrubRange(rhythm: AlertnessRhythm, now: Date,
                               window: (start: Date, end: Date), type: NapType) -> (earliest: Date, latest: Date)? {
        let earliest = max(now, rhythm.wakeTime.addingTimeInterval(1800))
        let latest = window.end.addingTimeInterval(-(type.targetWakeAfterOnset + 3600))
        return latest > earliest ? (earliest, latest) : nil
    }

    private func activityRange(plan: ActivityPlan, now: Date,
                               window: (start: Date, end: Date)) -> (earliest: Date, latest: Date)? {
        guard plan.on else { return nil }
        let earliest = max(now, window.start)
        let latest = window.end.addingTimeInterval(-(plan.minutes * 60 + 1800))
        return latest > earliest ? (earliest, latest) : nil
    }

    private func clampNap(_ d: Date, to r: (earliest: Date, latest: Date)) -> Date {
        min(max(d, r.earliest), r.latest)
    }
}
