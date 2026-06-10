//
//  SleepBankComplication.swift
//  SleepBank Watch Widget
//
//  Watch face complications: today's banked naps at a glance, with a tap to open
//  the app. Reads the App Group summary the watch app writes on each nap.
//

import WidgetKit
import SwiftUI

struct NapComplicationEntry: TimelineEntry {
    let date: Date
    let napsToday: Int
    let minutesToday: Int
    let napActive: Bool
}

struct NapComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> NapComplicationEntry {
        NapComplicationEntry(date: .now, napsToday: 2, minutesToday: 38, napActive: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (NapComplicationEntry) -> Void) {
        completion(current())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NapComplicationEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [current()], policy: .after(next)))
    }
    private func current() -> NapComplicationEntry {
        NapComplicationEntry(
            date: .now,
            napsToday: SharedStore.napsToday,
            minutesToday: SharedStore.minutesToday,
            napActive: SharedStore.napActive
        )
    }
}

struct NapComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: NapComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:    circular
        case .accessoryCorner:      corner
        case .accessoryInline:      inline
        case .accessoryRectangular: rectangular
        default:                    circular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "moon.zzz.fill").font(.caption2)
                Text(entry.napActive ? "•" : "\(entry.minutesToday)")
                    .font(.system(.headline, design: .rounded).bold())
            }
        }
        .widgetLabel("\(entry.minutesToday) min napped")
    }

    private var corner: some View {
        Image(systemName: "moon.zzz.fill")
            .widgetLabel(entry.napActive ? "Napping…" : "\(entry.minutesToday) min")
    }

    private var inline: some View {
        Label(entry.napActive ? "Napping…" : "\(entry.minutesToday) min napped",
              systemImage: "moon.zzz.fill")
    }

    private var rectangular: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Label("SleepBank", systemImage: "moon.zzz.fill").font(.caption2).foregroundStyle(.indigo)
                Text(entry.napActive ? "Napping…" : "\(entry.minutesToday) min · \(entry.napsToday) naps")
                    .font(.headline)
            }
            Spacer()
        }
    }
}

struct SleepBankComplication: Widget {
    let kind = "SleepBankComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NapComplicationProvider()) { entry in
            NapComplicationView(entry: entry)
                .widgetURL(URL(string: "sleepbank://nap"))
        }
        .configurationDisplayName("Naps Today")
        .description("Sleep you've banked in naps today.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Morning-light streak complication

struct MorningLightEntry: TimelineEntry {
    let date: Date
    let streak: Int
}

struct MorningLightProvider: TimelineProvider {
    func placeholder(in context: Context) -> MorningLightEntry {
        MorningLightEntry(date: .now, streak: 4)
    }
    func getSnapshot(in context: Context, completion: @escaping (MorningLightEntry) -> Void) {
        completion(current())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MorningLightEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now
        completion(Timeline(entries: [current()], policy: .after(next)))
    }
    private func current() -> MorningLightEntry {
        MorningLightEntry(date: .now, streak: SharedStore.morningLightStreak)
    }
}

struct MorningLightView: View {
    @Environment(\.widgetFamily) var family
    let entry: MorningLightEntry

    var body: some View {
        switch family {
        case .accessoryCorner:      corner
        case .accessoryInline:      inline
        case .accessoryRectangular: rectangular
        default:                    circular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "sun.max.fill").font(.caption2)
                Text("\(entry.streak)").font(.system(.headline, design: .rounded).bold())
            }
        }
        .widgetLabel("\(entry.streak)-day morning light")
    }

    private var corner: some View {
        Image(systemName: "sun.max.fill")
            .widgetLabel("\(entry.streak)-day 🌅")
    }

    private var inline: some View {
        Label("\(entry.streak)-day morning light", systemImage: "sun.max.fill")
    }

    private var rectangular: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Label("Morning Light", systemImage: "sun.max.fill").font(.caption2).foregroundStyle(.orange)
                Text(entry.streak > 0 ? "🌅 \(entry.streak)-day streak" : "Get morning light")
                    .font(.headline)
            }
            Spacer()
        }
    }
}

struct MorningLightComplication: Widget {
    let kind = "MorningLightComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MorningLightProvider()) { entry in
            MorningLightView(entry: entry)
                .widgetURL(URL(string: "sleepbank://daylight"))
        }
        .configurationDisplayName("Morning Light")
        .description("Your morning-light streak — consecutive days you got daylight early.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Today's Plan complication (next action)

struct PlanComplicationEntry: TimelineEntry {
    let date: Date
    let kind: String?
    let time: Date?
    let hasPlan: Bool
}

struct PlanComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanComplicationEntry {
        PlanComplicationEntry(date: .now, kind: "nap", time: .now, hasPlan: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (PlanComplicationEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanComplicationEntry>) -> Void) {
        // Half-hourly entries so the "next action" advances as each time passes.
        var entries: [PlanComplicationEntry] = []
        for step in 0..<32 {
            let date = Calendar.current.date(byAdding: .minute, value: step * 30, to: .now) ?? .now
            entries.append(entry(at: date))
        }
        let refresh = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
    private func entry(at date: Date) -> PlanComplicationEntry {
        guard let data = SharedStore.planSummary,
              let plan = try? JSONDecoder().decode(PlanSummary.self, from: data) else {
            return PlanComplicationEntry(date: date, kind: nil, time: nil, hasPlan: false)
        }
        let next = plan.next(at: date)
        return PlanComplicationEntry(date: date, kind: next?.kind, time: next?.time, hasPlan: true)
    }
}

struct PlanComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: PlanComplicationEntry

    private var info: (icon: String, label: String) {
        switch entry.kind {
        case "morningLight":    return ("sun.max.fill", "Light")
        case "morningMovement": return ("figure.walk", "Move")
        case "nap":             return ("moon.zzz.fill", "Nap")
        case "dip":             return ("arrow.down.right", "Dip")
        case "windDown":        return ("bed.double.fill", "Wind down")
        default:                return ("list.bullet.clipboard.fill", "Plan")
        }
    }

    private var timeText: String {
        guard entry.hasPlan else { return "—" }
        guard let t = entry.time else { return "now" }
        return t.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        switch family {
        case .accessoryCorner:      corner
        case .accessoryInline:      inline
        case .accessoryRectangular: rectangular
        default:                    circular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: info.icon).font(.caption2)
                Text(entry.hasPlan ? timeText : "—").font(.system(.caption, design: .rounded).bold())
            }
        }
        .widgetLabel(entry.hasPlan ? "\(info.label) \(timeText)" : "Open SleepBank")
    }

    private var corner: some View {
        Image(systemName: info.icon)
            .widgetLabel(entry.hasPlan ? "\(info.label) · \(timeText)" : "Plan")
    }

    private var inline: some View {
        Label(entry.hasPlan ? "Next: \(info.label) \(timeText)" : "SleepBank plan", systemImage: info.icon)
    }

    private var rectangular: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Label("Today's Plan", systemImage: "list.bullet.clipboard.fill")
                    .font(.caption2).foregroundStyle(.teal)
                Text(entry.hasPlan ? "Next: \(info.label) · \(timeText)" : "Open SleepBank on iPhone")
                    .font(.headline)
            }
            Spacer()
        }
    }
}

struct PlanComplication: Widget {
    let kind = "PlanComplication"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlanComplicationProvider()) { entry in
            PlanComplicationView(entry: entry)
                .widgetURL(URL(string: "sleepbank://plan"))
        }
        .configurationDisplayName("Today's Plan")
        .description("Your next move — get light, nap before the dip, wind down.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct SleepBankWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        SleepBankComplication()
        MorningLightComplication()
        PlanComplication()
    }
}
