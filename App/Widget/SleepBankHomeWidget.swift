//
//  SleepBankHomeWidget.swift
//  SleepBank Widget
//
//  Home-screen and Smart-Stack / lock-screen widget: today's banked naps at a
//  glance, plus last-night sleep and resting HR. Reads the App Group summary the
//  app keeps up to date.
//

import WidgetKit
import SwiftUI

struct SleepBankEntry: TimelineEntry {
    let date: Date
    let napsToday: Int
    let minutesToday: Int
    let napActive: Bool
    let lastNightHours: Double
    let restingHR: Int
}

struct SleepBankProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepBankEntry {
        SleepBankEntry(date: .now, napsToday: 2, minutesToday: 38, napActive: false, lastNightHours: 6.1, restingHR: 58)
    }
    func getSnapshot(in context: Context, completion: @escaping (SleepBankEntry) -> Void) {
        completion(current())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepBankEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [current()], policy: .after(next)))
    }
    private func current() -> SleepBankEntry {
        SleepBankEntry(
            date: .now,
            napsToday: SharedStore.napsToday,
            minutesToday: SharedStore.minutesToday,
            napActive: SharedStore.napActive,
            lastNightHours: SharedStore.lastNightHours,
            restingHR: SharedStore.restingHR
        )
    }
}

struct SleepBankWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SleepBankEntry

    var body: some View {
        switch family {
        case .systemMedium:        medium
        case .accessoryCircular:   circular
        case .accessoryRectangular: rectangular
        default:                   small
        }
    }

    private var small: some View {
        VStack(spacing: 6) {
            if entry.napActive {
                Image(systemName: "moon.zzz.fill").font(.title).foregroundStyle(.indigo)
                    .symbolEffect(.pulse)
                Text("Napping…").font(.caption.bold())
            } else {
                Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(.indigo)
                Text("\(entry.minutesToday) min").font(.system(.title, design: .rounded).bold())
                Text("banked today").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("\(entry.minutesToday)").font(.system(.largeTitle, design: .rounded).bold())
                Text("min napped").font(.caption2).foregroundStyle(.secondary)
                Text("\(entry.napsToday) nap\(entry.napsToday == 1 ? "" : "s") today").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if entry.napActive {
                    Label("Napping now", systemImage: "moon.zzz.fill").font(.caption.bold()).foregroundStyle(.indigo)
                }
                if entry.lastNightHours > 0 {
                    Label(String(format: "%.1fh last night", entry.lastNightHours), systemImage: "bed.double.fill")
                        .font(.caption).foregroundStyle(.indigo)
                }
                if entry.restingHR > 0 {
                    Label("\(entry.restingHR) bpm resting", systemImage: "heart.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "moon.zzz.fill").font(.caption2)
                Text("\(entry.minutesToday)").font(.system(.headline, design: .rounded).bold())
            }
        }
    }

    private var rectangular: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label("SleepBank", systemImage: "moon.zzz.fill").font(.caption).foregroundStyle(.indigo)
                Text(entry.napActive ? "Napping…" : "\(entry.minutesToday) min · \(entry.napsToday) naps")
                    .font(.headline)
                if entry.lastNightHours > 0 {
                    Text(String(format: "%.1fh last night", entry.lastNightHours))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct SleepBankHomeWidget: Widget {
    let kind = "SleepBankHomeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepBankProvider()) { entry in
            SleepBankWidgetView(entry: entry)
        }
        .configurationDisplayName("SleepBank")
        .description("Today's banked naps, last night's sleep, and resting heart rate.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
