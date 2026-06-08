//
//  NapLiveActivityView.swift
//  SleepBank Widget
//
//  The nap Live Activity: a lock-screen banner and Dynamic Island showing the
//  nap counting down to its smart wake, the current phase, and heart rate. The
//  countdown uses Text(timerInterval:) so it ticks natively — we only push
//  updates on phase/HR changes, which keeps it easy on the activity budget.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct NapLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NapActivityAttributes.self) { context in
            lockScreen(context)
                .padding()
                .activityBackgroundTint(Color.indigo.opacity(0.25))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.napTitle, systemImage: "moon.zzz.fill")
                        .font(.caption).foregroundStyle(.indigo)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.heartRate > 0 {
                        Label("\(context.state.heartRate)", systemImage: "heart.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(phaseLabel(context.state.phase))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        countdown(context).font(.title3.monospacedDigit().bold())
                    }
                }
            } compactLeading: {
                Image(systemName: "moon.zzz.fill").foregroundStyle(.indigo)
            } compactTrailing: {
                countdown(context).font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "moon.zzz.fill").foregroundStyle(.indigo)
            }
        }
    }

    // MARK: - Lock screen

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<NapActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: context.state.phase == "waking" ? "alarm.waves.left.and.right.fill" : "moon.zzz.fill")
                .font(.system(size: 34))
                .foregroundStyle(context.state.phase == "waking" ? .orange : .indigo)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.napTitle).font(.headline)
                Text(phaseLabel(context.state.phase))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                countdown(context).font(.system(size: 28, weight: .semibold, design: .rounded))
                if context.state.heartRate > 0 {
                    Label("\(context.state.heartRate)", systemImage: "heart.fill")
                        .font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<NapActivityAttributes>) -> some View {
        if context.state.phase == "waking" {
            Text("Wake").foregroundStyle(.orange)
        } else if let target = context.state.wakeTarget, target > .now {
            Text(timerInterval: .now...target, countsDown: true)
        } else {
            Text("—")
        }
    }

    private func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "settling":   return "Settling…"
        case "monitoring": return "Watching for sleep"
        case "asleep":     return "Asleep · wake armed"
        case "waking":     return "Time to wake"
        default:           return ""
        }
    }
}
