//
//  SleepChartWatchView.swift
//  SleepBank Watch App
//
//  Proves SleepChartKit ports to the watch unchanged. The wide timeline style is
//  cramped on a watch face, so we use the circular style here — same kit, same
//  SleepSample data, a layout that fits the wrist. Shows the real last-night
//  timeline synced from the phone when available, sample data otherwise.
//

import SwiftUI
import SleepChartKit

struct SleepChartWatchView: View {
    @State private var sync = WatchConnectivityService.shared

    private var samples: [SleepSample] {
        sync.lastNightSamples.isEmpty ? Self.sampleNight : sync.lastNightSamples
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                SleepChartView(samples: samples, style: .circular)
                    .frame(height: 170)
                Text(sync.lastNightSamples.isEmpty ? "Sample · open the phone app to sync" : "Last night")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("Sleep")
    }

    private static var sampleNight: [SleepSample] {
        let base = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
        func at(_ m: Int) -> Date { base.addingTimeInterval(TimeInterval(m * 60)) }
        return [
            SleepSample(stage: .awake, startDate: at(0), endDate: at(8)),
            SleepSample(stage: .asleepCore, startDate: at(8), endDate: at(55)),
            SleepSample(stage: .asleepDeep, startDate: at(55), endDate: at(95)),
            SleepSample(stage: .asleepCore, startDate: at(95), endDate: at(150)),
            SleepSample(stage: .asleepREM, startDate: at(150), endDate: at(180)),
            SleepSample(stage: .asleepCore, startDate: at(180), endDate: at(240)),
            SleepSample(stage: .asleepDeep, startDate: at(240), endDate: at(270)),
            SleepSample(stage: .asleepREM, startDate: at(270), endDate: at(320)),
        ]
    }
}

#Preview {
    NavigationStack { SleepChartWatchView() }
}
