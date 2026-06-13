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
        // Daylight changes slowly; reload hourly, but no later than the next midnight
        // so the day rollover zeros yesterday's numbers (the app repopulates real
        // values on its next foreground/refresh).
        let now = Date()
        let cal = Calendar.current
        let hourly = cal.date(byAdding: .hour, value: 1, to: now) ?? now
        let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        completion(Timeline(entries: [entry()], policy: .after(min(hourly, midnight))))
    }

    private func entry() -> DaylightEntry {
        // If the stored values weren't written today, they're yesterday's — show today
        // zeros ("none yet") rather than stale minutes. The streak still stands.
        let fresh = Calendar.current.isDateInToday(Date(timeIntervalSince1970: SharedStore.lastRefreshAt))
        return DaylightEntry(date: .now,
                             totalMin: fresh ? SharedStore.daylightTotalMin : 0,
                             morningMin: fresh ? SharedStore.daylightMorningMin : 0,
                             activityMin: fresh ? SharedStore.morningActivityMin : 0,
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
