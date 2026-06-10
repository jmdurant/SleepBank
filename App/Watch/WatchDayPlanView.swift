//
//  WatchDayPlanView.swift
//  SleepBank Watch App
//
//  Today's Plan on the wrist — the readiness "response layer", computed on the
//  watch from the rhythm snapshot the phone syncs. Compact: how the day starts,
//  then the timed agenda (light → move → nap before the dip → wind down).
//

import SwiftUI
import SleepBankCore

struct WatchDayPlanView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 600)) { context in
            if let snapshot = RhythmSnapshot.load() {
                let plan = DayPlan.build(rhythm: snapshot.rebuild(), now: context.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        header(plan)
                        ForEach(Array(plan.items.enumerated()), id: \.offset) { _, item in
                            row(item, plan: plan)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } else {
                ContentUnavailableView("Open SleepBank on iPhone",
                                       systemImage: "iphone",
                                       description: Text("Your day's plan syncs from your phone."))
            }
        }
        .navigationTitle("Today's Plan")
    }

    private func header(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(pct(plan.startingLevel))% to start")
                .font(.system(.title3, design: .rounded).bold())
            Text(plan.isShortNight ? "Short night — get through it well." : "Starting strong.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func row(_ item: DayPlan.Item, plan: DayPlan) -> some View {
        let s = style(item.kind)
        return HStack(spacing: 8) {
            Image(systemName: item.done ? "checkmark" : s.icon)
                .font(.caption).foregroundStyle(item.done ? .secondary : s.tint).frame(width: 18)
            Text(title(item)).font(.caption).foregroundStyle(item.done ? .secondary : .primary)
            Spacer()
            Text(timeLabel(item)).font(.caption2.weight(.medium))
                .foregroundStyle(item.done ? .secondary : s.tint)
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .opacity(item.done ? 0.7 : 1)
    }

    private func style(_ kind: DayPlan.Kind) -> (icon: String, tint: Color) {
        switch kind {
        case .morningLight:    return ("sun.max.fill", .orange)
        case .morningMovement: return ("figure.walk", .green)
        case .nap:             return ("moon.zzz.fill", .indigo)
        case .dip:             return ("arrow.down.right", .red)
        case .windDown:        return ("bed.double.fill", .purple)
        }
    }

    private func title(_ item: DayPlan.Item) -> String {
        switch item.kind {
        case .morningLight:    return item.done ? "Morning light" : "Get morning light"
        case .morningMovement: return item.done ? "Moved" : "Move a little"
        case .nap:             return "Power nap"
        case .dip:             return "Energy dip"
        case .windDown:        return "Wind down"
        }
    }

    private func timeLabel(_ item: DayPlan.Item) -> String {
        if item.done { return "✓" }
        guard let time = item.time else { return "Now" }
        return time.formatted(.dateTime.hour().minute())
    }

    private func pct(_ level: Double) -> Int { Int((level * 100).rounded()) }
}
