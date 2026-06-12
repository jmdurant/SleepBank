//
//  AlertnessWidget.swift
//  SleepBank Widget
//
//  Home- and lock-screen widget for the "you are here" alertness number and the
//  morning-light streak. Reads the App Group rhythm snapshot the app writes and
//  computes the level itself at each timeline entry, so the % tracks the day's
//  rise/dip/second-wind even between app launches.
//

import WidgetKit
import SwiftUI
import SleepBankCore

struct AlertnessEntry: TimelineEntry {
    let date: Date
    let level: Double
    let phase: String
    let streak: Int
    let hasData: Bool
}

struct AlertnessProviderWidget: TimelineProvider {
    func placeholder(in context: Context) -> AlertnessEntry {
        AlertnessEntry(date: .now, level: 0.62, phase: "Post-lunch dip", streak: 4, hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (AlertnessEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlertnessEntry>) -> Void) {
        // Emit half-hourly entries through the rest of the day so the % tracks the
        // curve without needing the app to refresh.
        var entries: [AlertnessEntry] = []
        let now = Date()
        for step in 0..<32 {
            let date = Calendar.current.date(byAdding: .minute, value: step * 30, to: now) ?? now
            entries.append(entry(at: date))
        }
        let refresh = Calendar.current.date(byAdding: .hour, value: 2, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func entry(at date: Date) -> AlertnessEntry {
        guard let snap = RhythmSnapshot.load() else {
            return AlertnessEntry(date: date, level: 0, phase: AlertnessRhythm.phaseLabel(at: date),
                                  streak: SharedStore.morningLightStreak, hasData: false)
        }
        let rhythm = snap.rebuild()
        return AlertnessEntry(date: date, level: rhythm.level(at: date),
                              phase: AlertnessRhythm.phaseLabel(at: date),
                              streak: snap.morningLightStreak, hasData: true)
    }
}

struct AlertnessWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: AlertnessEntry

    private var pct: Int { Int((entry.level * 100).rounded()) }

    var body: some View {
        switch family {
        case .accessoryCircular:    circular
        case .accessoryRectangular: rectangular
        case .accessoryInline:      inlineView
        case .systemMedium:         medium
        default:                    small
        }
    }

    // Mirrors the app's Alertness tile: header + the score ring with the live %.
    private var small: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.sand)
                Text("Alertness").font(.caption.weight(.semibold))
                Spacer()
            }
            Spacer(minLength: 0)
            ring
            Spacer(minLength: 0)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.001, entry.hasData ? entry.level : 0.001))
                .stroke(
                    AngularGradient(colors: Self.tint(for: entry.level), center: .center,
                                    startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(entry.hasData ? "\(pct)" : "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                Text(entry.phase).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(width: 96, height: 96)
    }

    static func tint(for level: Double) -> [Color] {
        switch level {
        case 0.66...:     return [.aqua, .mint]
        case 0.4..<0.66:  return [.ocean, .tide]
        case 0.2..<0.4:   return [.sand, Color(red: 0.82, green: 0.64, blue: 0.40)]
        default:          return [Color(red: 0.72, green: 0.55, blue: 0.32), .sand]
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(entry.hasData ? "\(pct)%" : "—")
                    .font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                Text("alert now").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label(entry.phase, systemImage: "bolt.fill").font(.caption.bold()).foregroundStyle(.indigo)
                if entry.streak > 0 {
                    Label("🌅 \(entry.streak)-day morning-light streak", systemImage: "sun.max.fill")
                        .font(.caption).foregroundStyle(.orange)
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
                Image(systemName: "bolt.fill").font(.caption2)
                Text(entry.hasData ? "\(pct)" : "—").font(.system(.headline, design: .rounded).bold())
            }
        }
    }

    private var rectangular: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label("Alertness", systemImage: "bolt.fill").font(.caption).foregroundStyle(.yellow)
                Text(entry.hasData ? "\(pct)% · \(entry.phase)" : "Open SleepBank").font(.headline)
                if entry.streak > 0 {
                    Text("🌅 \(entry.streak)-day morning light").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var inlineView: some View {
        Text(entry.hasData ? "⚡︎ \(pct)% · \(entry.phase)" : "SleepBank")
    }
}

struct AlertnessWidget: Widget {
    let kind = "AlertnessWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AlertnessProviderWidget()) { entry in
            AlertnessWidgetView(entry: entry)
                .widgetURL(URL(string: "sleepbank://alertness"))
        }
        .configurationDisplayName("Alertness")
        .description("Your predicted alertness right now and your morning-light streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
