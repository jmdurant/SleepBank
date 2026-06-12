//
//  DaylightWidget.swift
//  SleepBank Widget
//
//  Home-screen widget that mirrors the app's Daylight tile: today's total daylight
//  minutes, the morning portion, morning movement, and the morning-light streak.
//  Reads the App Group values the app writes on each HealthKit refresh.
//

import WidgetKit
import SwiftUI

struct DaylightEntry: TimelineEntry {
    let date: Date
    let totalMin: Int
    let morningMin: Int
    let activityMin: Int
    let streak: Int
}

struct DaylightProviderWidget: TimelineProvider {
    func placeholder(in context: Context) -> DaylightEntry {
        DaylightEntry(date: .now, totalMin: 28, morningMin: 18, activityMin: 12, streak: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (DaylightEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DaylightEntry>) -> Void) {
        // Daylight changes slowly; one entry, refresh in an hour (the app also reloads
        // the timeline on every HealthKit refresh).
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry()], policy: .after(refresh)))
    }

    private func entry() -> DaylightEntry {
        DaylightEntry(date: .now,
                      totalMin: SharedStore.daylightTotalMin,
                      morningMin: SharedStore.daylightMorningMin,
                      activityMin: SharedStore.morningActivityMin,
                      streak: SharedStore.morningLightStreak)
    }
}

struct DaylightWidgetView: View {
    let entry: DaylightEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill").font(.caption2).foregroundStyle(.sand)
                Text("Daylight").font(.caption.weight(.semibold))
                Spacer()
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(entry.totalMin)")
                    .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                Text("min").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(entry.morningMin >= 1 ? "\(entry.morningMin) min this morning" : "none yet this morning")
                .font(.caption2).foregroundStyle(.secondary)
            if entry.activityMin >= 1 {
                Text("\(entry.activityMin) min activity this morning")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.streak > 0 {
                Text("🌅 \(entry.streak)-day streak").font(.caption2.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct DaylightWidget: Widget {
    let kind = "DaylightWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DaylightProviderWidget()) { entry in
            DaylightWidgetView(entry: entry)
                .widgetURL(URL(string: "sleepbank://daylight"))
        }
        .configurationDisplayName("Daylight")
        .description("Today's daylight, morning light & movement, and your streak.")
        .supportedFamilies([.systemSmall])
    }
}
