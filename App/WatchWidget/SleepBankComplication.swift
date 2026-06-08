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

@main
struct SleepBankWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        SleepBankComplication()
    }
}
