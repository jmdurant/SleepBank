//
//  ContentView.swift
//  SleepBank
//
//  Phone-side shell for the first milestone. Pulls last-night sleep + heart
//  context from HealthKit and renders it with the existing SleepChartKit. The
//  nap history / "sleep bank" surfaces land here next; for now it confirms the
//  health pipeline and the chart kit are wired into the app.
//

import SwiftUI
import WidgetKit
import SleepChartKit

struct ContentView: View {
    @State private var health = HealthKitService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    EnergyRingView()
                    AlertnessCurveView()
                    NavigationLink {
                        NapView()
                    } label: {
                        Label("Start a Nap", systemImage: "moon.zzz.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.indigo, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    lastNightCard
                    chartCard
                    contextCard
                    NavigationLink {
                        LiveView()
                    } label: {
                        Label("Live Data — HR & EEG", systemImage: "waveform.path.ecg.rectangle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    NavigationLink {
                        SensorsView()
                    } label: {
                        Label("Sensors — Muse & H10", systemImage: "sensor.tag.radiowaves.forward")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    NavigationLink {
                        SoundsView()
                    } label: {
                        Label("Relaxing Sounds", systemImage: "speaker.wave.2.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    NavigationLink {
                        ValidationView()
                    } label: {
                        Label("Validation & Training Data", systemImage: "checklist")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .navigationTitle("SleepBank")
            .task {
                if await health.requestAuthorization() {
                    await health.refreshAll()
                    // Push the real last-night timeline to the watch.
                    PhoneConnectivity.shared.sendLastNight(health.lastNightSamples)
                    // Update the home widget's health summary.
                    SharedStore.lastNightHours = health.lastNightSleep?.totalHours ?? 0
                    SharedStore.restingHR = Int(health.restingHeartRate)
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    private var lastNightCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last Night").font(.headline)
            if let s = health.lastNightSleep {
                Text(String(format: "%.1f h asleep · %.0f%% efficiency", s.totalHours, s.efficiency * 100))
                    .font(.subheadline)
                Text(String(format: "7-day average: %.1f h", health.sleepAverage7Day))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No sleep data yet — grant Health access to see your night.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Stages").font(.headline)
            if health.lastNightSamples.isEmpty {
                Text("Charting sample data — grant Health access for your real night.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SleepChartView(
                samples: health.lastNightSamples.isEmpty ? Self.sampleNight : health.lastNightSamples,
                style: .timeline
            )
            .frame(height: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's Baseline").font(.headline)
            Label(health.restingHeartRate > 0 ? "\(Int(health.restingHeartRate)) bpm resting (\(health.restingHRTrend))" : "Resting HR —",
                  systemImage: "heart.fill")
            Label(health.hrvAverage > 0 ? String(format: "%.0f ms HRV", health.hrvAverage) : "HRV —",
                  systemImage: "waveform.path.ecg")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Placeholder timeline so the chart renders before live data exists.
    private static var sampleNight: [SleepSample] {
        let base = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
        func at(_ minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }
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
    ContentView()
}
