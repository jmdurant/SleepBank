//
//  NapRecapView.swift
//  SleepBank Watch App
//
//  Immediate feedback after a nap: a compact chart of the session (settling →
//  asleep → wake) plus the numbers that matter — how long until you fell asleep
//  and how much sleep you actually banked.
//

import SwiftUI
import SleepChartKit
import SleepBankCore

struct NapRecapView: View {
    let record: NapRecord
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Nap complete")
                    .font(.headline)

                SleepChartView(samples: NapChart.samples(from: record), style: .timeline)
                    .frame(height: 90)

                VStack(spacing: 4) {
                    if record.onset != nil {
                        stat("Asleep", "\(Int(record.asleepDuration / 60)) min", .indigo)
                        if let latency = NapChart.onsetLatencyMinutes(record) {
                            stat("Fell asleep in", "\(latency) min", .secondary)
                        }
                    } else {
                        Text("Didn't detect sleep this time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    stat("Woke via", wakeText, .secondary)
                }

                Button(action: onDone) {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).foregroundStyle(color == .secondary ? .secondary : color)
        }
    }

    private var wakeText: String {
        switch record.wakeReason {
        case .reachedTarget: return "smart alarm"
        case .deepening: return "deep sleep nearing"
        case .ceiling: return "time limit"
        case .spontaneous: return "woke naturally"
        case .manual, .none: return "you"
        }
    }
}
