//
//  NapView.swift
//  SleepBank
//
//  Start and run a nap from the phone — the at-home mode. Mirrors the watch nap
//  UI: pick a type, watch it progress with a live wake countdown and the paired
//  sensors, clear the alarm on wake, see a recap.
//

import SwiftUI
import SleepChartKit
import SleepBankCore

struct NapView: View {
    @State private var nap = PhoneNapController.shared

    var body: some View {
        Group {
            if nap.isAlarming {
                alarmView
            } else if nap.isNapping {
                activeSession
            } else if let record = nap.lastCompletedNap {
                recap(record)
            } else {
                picker
            }
        }
        .navigationTitle("Nap")
        .padding(.horizontal)
    }

    // MARK: - Pick a nap

    private var picker: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 44)).foregroundStyle(.indigo)
            ForEach(NapType.allCases, id: \.self) { type in
                Button {
                    nap.start(type: type)
                } label: {
                    VStack(spacing: 2) {
                        Text(type.title).font(.headline)
                        Text(type.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(type == .power ? .indigo : .teal)
            }
            Text("Uses the paired Polar H10 and Muse when connected. Open Sensors to connect them.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    // MARK: - Active

    private var activeSession: some View {
        VStack(spacing: 14) {
            Text(nap.phaseLabel).font(.subheadline).foregroundStyle(.secondary)
            Text(nap.countdownLabel)
                .font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(nap.onsetDetected ? "until wake" : "max remaining")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 18) {
                stat("heart.fill", .red, nap.heartRate > 0 ? "\(nap.heartRate)" : "--", "bpm")
                stat("waveform.path.ecg", .pink, nap.hrv > 0 ? String(format: "%.0f", nap.hrv) : "--", "HRV")
                stat("lungs.fill", .teal, nap.breathingRate > 0 ? String(format: "%.0f", nap.breathingRate) : "--", "br/min")
                stat("brain.head.profile", nap.museGood ? .purple : .gray,
                     nap.museGood ? "EEG" : "—", nap.museGood ? "good" : "no sig")
            }
            if nap.spo2 > 0 {
                Label(String(format: "SpO₂ %.0f%%", nap.spo2), systemImage: "drop.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Group {
                if let err = LiveActivityManager.shared.lastError {
                    Text("Live Activity: \(err)")
                } else if LiveActivityManager.shared.enabled {
                    Text("Live Activity active — see it on the Lock Screen / Dynamic Island")
                } else {
                    Text("Live Activities are off in Settings → SleepBank")
                }
            }
            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Button(role: .destructive) { nap.stop() } label: {
                Label("End nap", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
    }

    private func stat(_ icon: String, _ color: Color, _ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title3.monospacedDigit().bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Alarm

    private var alarmView: some View {
        VStack(spacing: 18) {
            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.system(size: 60)).foregroundStyle(.orange).symbolEffect(.pulse)
            Text("Time to wake").font(.title2.bold())
            Button { nap.stop() } label: {
                Label("I'm up", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(.green)
        }
    }

    // MARK: - Recap

    private func recap(_ record: NapRecord) -> some View {
        VStack(spacing: 14) {
            Text("Nap complete").font(.title3.bold())
            SleepChartView(samples: NapChart.samples(from: record), style: .timeline)
                .frame(height: 120)
            if record.onset != nil {
                Text("\(Int(record.asleepDuration / 60)) min asleep").font(.headline)
                if let lat = NapChart.onsetLatencyMinutes(record) {
                    Text("Fell asleep in \(lat) min").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Didn't detect sleep this time").font(.subheadline).foregroundStyle(.secondary)
            }
            Button { nap.dismissRecap() } label: {
                Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(.green)
        }
    }
}

#Preview {
    NavigationStack { NapView() }
}
