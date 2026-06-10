//
//  AlertnessCurveView.swift
//  SleepBank
//
//  The day's predicted alertness rhythm (two-process model), plus an interactive
//  planner: add any number of naps, walks, and workouts, drag each along the curve,
//  and watch the combined "your plan" line lift in real time — then schedule them.
//  Late or bright-evening additions turn orange (they'd cost tonight's sleep).
//

import SwiftUI
import Charts
import SleepBankCore

struct AlertnessCurveView: View {
    var health = HealthKitService.shared
    var store = NapDecisionStore.shared

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

    /// One planned intervention. Multiples of any kind are allowed.
    struct PlanItem: Identifiable {
        let id = UUID()
        var kind: Intervention
        var napType: NapType = .power
        var at: Date?
        var minutes: Double
        var outdoors: Bool
        static func make(_ kind: Intervention) -> PlanItem {
            PlanItem(kind: kind, minutes: kind == .workout ? 60 : 30, outdoors: kind != .workout)
        }
    }

    /// A resolved item: its placed span and the model object it produces.
    struct Resolved {
        let item: PlanItem
        let start: Date
        let end: Date
        let nap: AlertnessRhythm.Nap?
        let activity: AlertnessRhythm.Activity?
    }

    struct Marker: Identifiable {
        let id: UUID
        let kind: Intervention
        let start: Date
        let level: Double
        let late: Bool
        let lightLate: Bool
    }
    struct Band: Identifiable { let id: UUID; let start: Date; let end: Date; let late: Bool }
    struct GainPoint { let date: Date; let bare: Double; let actual: Double }

    @State private var items: [PlanItem] = [.make(.nap)]
    @State private var focusedID: UUID?
    @State private var scheduledKey: String?
    @State private var editing = false
    @State private var isDragging = false

    private var focused: PlanItem? { items.first { $0.id == focusedID } ?? items.first }

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

            let resolved = resolveItems(rhythm: rhythm, now: now, window: window)
            let naps = resolved.compactMap(\.nap)
            let activities = resolved.compactMap(\.activity)
            let planStart = resolved.map(\.start).min()
            let projection: [AlertnessRhythm.Reading] = planStart.map {
                rhythm.planReadings(naps: naps, activities: activities, from: $0, to: window.end, step: 300)
            } ?? []
            let markers = buildMarkers(resolved: resolved, rhythm: rhythm, now: now, naps: naps, activities: activities)
            let bands = resolved.map { r in
                Band(id: r.item.id, start: r.start, end: r.end,
                     late: markers.first { $0.id == r.item.id }?.late ?? false)
            }
            let yRange = yDomain(baseline: baseline, ideal: idealReadings, projection: projection, nowLevel: nowLevel)
            let onDrag = makeDragHandler(resolved: resolved, markers: markers, rhythm: rhythm, now: now, window: window)
            let peak = projection.max(by: { $0.level < $1.level })

            VStack(alignment: .leading, spacing: 10) {
                header(rhythm: rhythm, now: now, markers: markers)
                chart(baseline: baseline, projection: projection, ideal: idealReadings, gain: gain,
                      now: now, nowLevel: nowLevel, yRange: yRange, markers: markers, bands: bands, onDrag: onDrag)
                    .frame(height: 170)
                legend(hasPlan: !projection.isEmpty, planLate: markers.contains { $0.late })
                interventionPicker(markers: markers)
                if focused?.kind == .nap { napTypeToggle }
                readout(rhythm: rhythm, markers: markers, projection: projection)
                Divider()
                daylightRow()
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .sheet(isPresented: $editing) { activityEditor }
            .onAppear { PlanPreview.shared.level = peak?.level; PlanPreview.shared.peakTime = peak?.date }
            .onChange(of: peak?.level) { _, lvl in
                PlanPreview.shared.level = lvl; PlanPreview.shared.peakTime = peak?.date
            }
            .onDisappear { PlanPreview.shared.level = nil; PlanPreview.shared.peakTime = nil }
        }
    }

    // MARK: - Header (live icon + time + schedule)

    private func header(rhythm: AlertnessRhythm, now: Date, markers: [Marker]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Your day · \(AlertnessProvider.phaseLabel(now))").font(.headline)
                Spacer()
                if let m = focusedMarker(markers) {
                    HStack(spacing: 4) {
                        Image(systemName: m.late ? "exclamationmark.triangle.fill" : m.kind.icon).font(.caption2)
                        Text(m.start, format: .dateTime.hour().minute())
                            .font(.subheadline.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
                    }
                    .foregroundStyle(m.late ? .orange : m.kind.tint)
                    scheduleButton(m)
                }
            }
            Text(whyLine(rhythm)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func scheduleButton(_ m: Marker) -> some View {
        let done = scheduledKey == key(m)
        let tint: Color = done ? .green : (m.late ? .orange : m.kind.tint)
        return Button {
            Task {
                let ok: Bool
                if m.kind == .nap {
                    ok = await PlanNotificationService.shared.scheduleNap(at: m.start, type: focused?.napType ?? .power)
                } else {
                    ok = await PlanNotificationService.shared.scheduleActivity(
                        at: m.start, title: m.kind.label, outdoors: focused?.outdoors ?? true,
                        minutes: focused?.minutes ?? 30)
                }
                if ok { scheduledKey = key(m) }
            }
        } label: {
            Image(systemName: done ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.title3).foregroundStyle(tint).symbolEffect(.bounce, value: done)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "Scheduled" : "Schedule \(m.kind.label)")
    }

    // MARK: - Picker + editors

    private func interventionPicker(markers: [Marker]) -> some View {
        HStack(spacing: 8) {
            ForEach(Intervention.allCases) { kind in
                let count = items.filter { $0.kind == kind }.count
                let isFocusedKind = focused?.kind == kind
                Button {
                    if let first = items.first(where: { $0.kind == kind }) { focusedID = first.id }
                    else { addItem(kind) }
                    scheduledKey = nil
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: kind.icon).font(.caption2)
                        Text(kind.label).font(.caption.weight(.medium))
                        if count == 1 { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                        else if count > 1 { Text("×\(count)").font(.caption2.weight(.bold)) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background((isFocusedKind ? kind.tint.opacity(0.22) : Color.secondary.opacity(0.12)), in: Capsule())
                    .foregroundStyle(isFocusedKind ? kind.tint : .secondary)
                    .overlay(Capsule().stroke(isFocusedKind ? kind.tint : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var napTypeToggle: some View {
        Picker("Nap type", selection: napTypeBinding) {
            Text("Power · 20 min").tag(NapType.power)
            Text("Cycle · 90 min").tag(NapType.cycle)
        }
        .pickerStyle(.segmented)
    }

    private var activityEditor: some View {
        Group {
            if let idx = items.firstIndex(where: { $0.id == focusedID }), items[idx].kind != .nap {
                NavigationStack {
                    Form {
                        Section(items[idx].kind.label) {
                            Stepper(value: $items[idx].minutes, in: 10...120, step: 5) {
                                Text("\(Int(items[idx].minutes)) min").monospacedDigit()
                            }
                            Picker("Where", selection: $items[idx].outdoors) {
                                Text("Outside ☀️").tag(true)
                                Text("Inside").tag(false)
                            }
                            .pickerStyle(.segmented)
                            Text(items[idx].outdoors
                                 ? "Outside adds daylight — anchors your rhythm and helps you sleep tonight."
                                 : "Indoors gives the movement boost without the light/anchoring benefit.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Edit \(items[idx].kind.label)")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } } }
                }
                .presentationDetents([.height(260)])
            }
        }
    }

    // MARK: - Readout

    @ViewBuilder
    private func readout(rhythm: AlertnessRhythm, markers: [Marker], projection: [AlertnessRhythm.Reading]) -> some View {
        if let m = focusedMarker(markers), let f = focused {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: m.late ? "exclamationmark.triangle.fill" : m.kind.icon)
                        .font(.caption2).foregroundStyle(m.late ? .orange : m.kind.tint)
                    Text(readoutText(m, rhythm: rhythm, projection: projection))
                        .font(.caption2).foregroundStyle(m.late ? .orange : .secondary)
                }
                HStack(spacing: 14) {
                    Button { addItem(f.kind) } label: {
                        Label("Add another \(f.kind.label.lowercased())", systemImage: "plus")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain).foregroundStyle(f.kind.tint)
                    if f.kind != .nap {
                        Button { editing = true } label: { Label("Edit", systemImage: "slider.horizontal.3").font(.caption2) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { removeFocused() } label: { Label("Remove", systemImage: "xmark").font(.caption2) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        } else if let g = gainNowPct(rhythm: rhythm, now: .now), hasInterventions(rhythm) {
            gainCallout(g, rhythm: rhythm)
        } else if let gap = idealGap(rhythm: rhythm, now: .now) {
            idealCallout(gap)
        }
    }

    private func readoutText(_ m: Marker, rhythm: AlertnessRhythm,
                             projection: [AlertnessRhythm.Reading]) -> LocalizedStringKey {
        let t = m.start.formatted(.dateTime.hour().minute())
        if m.kind == .nap {
            if m.late { return "A nap at **\(t)** is late — it keeps you alert near bedtime and may delay tonight's sleep." }
            let boost = peakBoost(projection: projection, rhythm: rhythm)
            return "Nap at **\(t)** → up by ~**\(boost)%** through the afternoon. Tap + to schedule."
        }
        let what = m.kind.label.lowercased()
        if m.late {
            return m.lightLate
                ? "A \(what) outside at **\(t)** is in bright evening light — this close to bed it can delay your sleep."
                : "A \(what) at **\(t)** is late — the arousal lingers and may delay tonight's sleep."
        }
        let morning = Calendar.current.component(.hour, from: m.start) < 11
        if (focused?.outdoors ?? false) && morning {
            return "A \(what) outside at **\(t)** → a lift now, **plus** it anchors your rhythm and helps you sleep tonight."
        }
        if focused?.outdoors ?? false {
            return "A \(what) outside at **\(t)** → a modest lift, plus daylight to steady your rhythm."
        }
        return "A \(what) at **\(t)** → a modest, ~1–2 h lift. Tap + to schedule."
    }

    private func peakBoost(projection: [AlertnessRhythm.Reading], rhythm: AlertnessRhythm) -> Int {
        guard let p = projection.max(by: { $0.level < $1.level }) else { return 0 }
        return max(0, Int(((p.level - rhythm.level(at: p.date)) * 100).rounded()))
    }

    private func whyLine(_ rhythm: AlertnessRhythm) -> String {
        var parts = [rhythm.isShortNight ? "Short night" : "Rested"]
        if !rhythm.naps.isEmpty { parts.append("\(rhythm.naps.count) nap\(rhythm.naps.count == 1 ? "" : "s")") }
        if rhythm.morningLightDose > 0.1 { parts.append("morning light ✓") }
        if rhythm.morningActivityDose > 0.1 { parts.append("AM movement ✓") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Chart

    private func chart(baseline: [AlertnessRhythm.Reading], projection: [AlertnessRhythm.Reading],
                       ideal: [AlertnessRhythm.Reading], gain: [GainPoint],
                       now: Date, nowLevel: Double, yRange: ClosedRange<Double>,
                       markers: [Marker], bands: [Band], onDrag: @escaping (Date, Bool) -> Void) -> some View {
        Chart {
            ForEach(baseline, id: \.date) { r in
                AreaMark(x: .value("Time", r.date), y: .value("Alertness", r.level))
                    .foregroundStyle(.linearGradient(colors: [.indigo.opacity(0.16), .indigo.opacity(0.01)],
                                                     startPoint: .top, endPoint: .bottom))
            }
            ForEach(bands) { b in
                RectangleMark(xStart: .value("From", b.start), xEnd: .value("To", b.end),
                              yStart: .value("lo", yRange.lowerBound), yEnd: .value("hi", yRange.upperBound))
                    .foregroundStyle((b.late ? Color.orange : .mint).opacity(0.10))
            }
            ForEach(gain, id: \.date) { g in
                AreaMark(x: .value("Time", g.date), yStart: .value("Floor", g.bare), yEnd: .value("You", g.actual))
                    .foregroundStyle(.green.opacity(0.22))
            }
            ForEach(gain, id: \.date) { g in
                LineMark(x: .value("Time", g.date), y: .value("Alertness", g.bare), series: .value("S", "floor"))
                    .foregroundStyle(.green.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3])).interpolationMethod(.catmullRom)
            }
            ForEach(ideal, id: \.date) { r in
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level), series: .value("S", "ideal"))
                    .foregroundStyle(.teal.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4])).interpolationMethod(.catmullRom)
            }
            ForEach(baseline, id: \.date) { r in
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level), series: .value("S", "you"))
                    .foregroundStyle(.indigo).interpolationMethod(.catmullRom)
            }
            let planLate = markers.contains { $0.late }
            ForEach(projection, id: \.date) { r in
                LineMark(x: .value("Time", r.date), y: .value("Alertness", r.level), series: .value("S", "plan"))
                    .foregroundStyle(planLate ? .orange : .mint)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4])).interpolationMethod(.catmullRom)
            }
            RuleMark(x: .value("Now", now))
                .foregroundStyle(.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("Now", now), y: .value("Alertness", nowLevel)).foregroundStyle(.white).symbolSize(120)
            PointMark(x: .value("Now", now), y: .value("Alertness", nowLevel)).foregroundStyle(.indigo).symbolSize(60)
            ForEach(markers) { m in
                let isFocused = m.id == focused?.id
                PointMark(x: .value("At", m.start), y: .value("Alertness", m.level))
                    .foregroundStyle(.white).symbolSize(isFocused ? 200 : 150)
                PointMark(x: .value("At", m.start), y: .value("Alertness", m.level))
                    .foregroundStyle(m.late ? .orange : m.kind.tint).symbolSize(isFocused ? 120 : 80)
                    .annotation(position: .top, spacing: 2) {
                        Image(systemName: m.late ? "exclamationmark.triangle.fill" : m.kind.icon)
                            .font(.system(size: 9)).foregroundStyle(m.late ? .orange : m.kind.tint)
                    }
            }
        }
        .chartYScale(domain: yRange)
        .chartYAxis(.hidden)
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 3)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame {
                    let rect = geo[plot]
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let x = v.location.x - rect.minX
                                if let date: Date = proxy.value(atX: x, as: Date.self) {
                                    onDrag(date, !isDragging); isDragging = true
                                }
                            }
                            .onEnded { _ in isDragging = false })
                        .onLongPressGesture { if focused?.kind != .nap { editing = true } }
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

    // MARK: - Plan resolution

    private func resolveItems(rhythm: AlertnessRhythm, now: Date, window: (start: Date, end: Date)) -> [Resolved] {
        var out: [Resolved] = []
        var occupied: [(Date, Date)] = []
        for item in items {
            let dur = item.kind == .nap ? item.napType.targetWakeAfterOnset : item.minutes * 60
            guard let range = itemRange(kind: item.kind, dur: dur, now: now, wake: rhythm.wakeTime, window: window) else { continue }
            let start: Date = item.at.map { snap(min(max($0, range.earliest), range.latest), dur: dur, range: range, obstacles: occupied) }
                              ?? firstFreeSlot(range: range, dur: dur, obstacles: occupied)
            let end = start.addingTimeInterval(dur)
            occupied.append((start, end))
            let nap = item.kind == .nap ? AlertnessRhythm.Nap(end: end, type: item.napType, fullness: 1) : nil
            let act = item.kind != .nap
                ? AlertnessRhythm.Activity(id: item.id.uuidString, intensity: item.kind == .walk ? .walk : .workout,
                                           outdoors: item.outdoors, start: start, duration: dur)
                : nil
            out.append(Resolved(item: item, start: start, end: end, nap: nap, activity: act))
        }
        return out
    }

    private func buildMarkers(resolved: [Resolved], rhythm: AlertnessRhythm, now: Date,
                              naps: [AlertnessRhythm.Nap], activities: [AlertnessRhythm.Activity]) -> [Marker] {
        let bedtime = rhythm.wakeTime.addingTimeInterval(16 * 3600)
        let sunset = localSunset(now: now)
        let preBed = bedtime.addingTimeInterval(-3 * 3600)
        let allAtBed = rhythm.level(at: bedtime, naps: naps, activities: activities)
        return resolved.map { r in
            let lvl = rhythm.level(at: r.start, naps: naps, activities: activities)
            let napsW = resolved.filter { $0.item.id != r.item.id }.compactMap(\.nap)
            let actsW = resolved.filter { $0.item.id != r.item.id }.compactMap(\.activity)
            let marginal = allAtBed - rhythm.level(at: bedtime, naps: napsW, activities: actsW)
            if r.item.kind == .nap {
                return Marker(id: r.item.id, kind: .nap, start: r.start, level: lvl, late: marginal >= 0.065, lightLate: false)
            }
            let lightLate = r.item.outdoors && r.start < sunset && r.start >= preBed
            return Marker(id: r.item.id, kind: r.item.kind, start: r.start, level: lvl,
                          late: marginal >= 0.035 || lightLate, lightLate: lightLate)
        }
    }

    private func makeDragHandler(resolved: [Resolved], markers: [Marker], rhythm: AlertnessRhythm,
                                 now: Date, window: (start: Date, end: Date)) -> (Date, Bool) -> Void {
        { raw, isFirstTouch in
            if isFirstTouch, let near = nearestMarker(to: raw, markers: markers) { focusedID = near.id; scheduledKey = nil }
            guard let fid = focusedID ?? items.first?.id, let idx = items.firstIndex(where: { $0.id == fid }) else { return }
            let item = items[idx]
            let dur = item.kind == .nap ? item.napType.targetWakeAfterOnset : item.minutes * 60
            guard let range = itemRange(kind: item.kind, dur: dur, now: now, wake: rhythm.wakeTime, window: window) else { return }
            let obstacles = resolved.filter { $0.item.id != fid }.map { ($0.start, $0.end) }
            items[idx].at = snap(raw, dur: dur, range: range, obstacles: obstacles)
            scheduledKey = nil
        }
    }

    private func nearestMarker(to date: Date, markers: [Marker]) -> Marker? {
        markers.filter { abs($0.start.timeIntervalSince(date)) <= 35 * 60 }
               .min { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
    }

    // MARK: - Item mutation

    private func addItem(_ kind: Intervention) {
        let item = PlanItem.make(kind)
        items.append(item); focusedID = item.id; scheduledKey = nil
    }
    private func removeFocused() {
        if let id = focusedID ?? items.first?.id { items.removeAll { $0.id == id } }
        focusedID = items.first?.id; scheduledKey = nil
    }
    private func focusedMarker(_ markers: [Marker]) -> Marker? {
        markers.first { $0.id == focused?.id } ?? markers.first
    }
    private var napTypeBinding: Binding<NapType> {
        Binding(get: { focused?.napType ?? .power },
                set: { v in if let idx = items.firstIndex(where: { $0.id == focusedID }) { items[idx].napType = v } })
    }
    private func key(_ m: Marker) -> String { "\(m.kind.rawValue)-\(Int(m.start.timeIntervalSinceReferenceDate / 60))" }

    // MARK: - Geometry helpers

    private func itemRange(kind: Intervention, dur: TimeInterval, now: Date, wake: Date,
                           window: (start: Date, end: Date)) -> (earliest: Date, latest: Date)? {
        let earliest = max(now, wake)
        let buffer: TimeInterval = kind == .nap ? 3600 : 1800
        let latest = window.end.addingTimeInterval(-(dur + buffer))
        return latest > earliest ? (earliest, latest) : nil
    }

    private func snap(_ raw: Date, dur: TimeInterval, range: (earliest: Date, latest: Date),
                      obstacles: [(Date, Date)]) -> Date {
        var start = min(max(raw, range.earliest), range.latest)
        for _ in 0..<6 {
            guard let ob = obstacles.first(where: { start < $0.1 && start.addingTimeInterval(dur) > $0.0 }) else { break }
            let before = ob.0.addingTimeInterval(-dur), after = ob.1
            let beforeOK = before >= range.earliest, afterOK = after <= range.latest
            if beforeOK && afterOK {
                start = abs(before.timeIntervalSince(raw)) <= abs(after.timeIntervalSince(raw)) ? before : after
            } else if beforeOK { start = before } else if afterOK { start = after } else { break }
        }
        return min(max(start, range.earliest), range.latest)
    }

    private func firstFreeSlot(range: (earliest: Date, latest: Date), dur: TimeInterval,
                               obstacles: [(Date, Date)]) -> Date {
        var t = range.earliest
        for ob in obstacles.sorted(by: { $0.0 < $1.0 }) where t < ob.1 && t.addingTimeInterval(dur) > ob.0 { t = ob.1 }
        return min(t, range.latest)
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

    // MARK: - Model wiring

    private func makeRhythm(now: Date) -> AlertnessRhythm { AlertnessProvider.rhythm(health: health, store: store, now: now) }

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
    private func gainReadings(rhythm: AlertnessRhythm, now: Date, window: (start: Date, end: Date)) -> [GainPoint] {
        guard hasInterventions(rhythm) else { return [] }
        let bare = bareRhythm(rhythm)
        let end = min(now, window.end)
        guard end > window.start else { return [] }
        var pts: [GainPoint] = []
        var t = window.start
        while t < end { pts.append(GainPoint(date: t, bare: bare.level(at: t), actual: rhythm.level(at: t))); t = t.addingTimeInterval(1200) }
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
}
