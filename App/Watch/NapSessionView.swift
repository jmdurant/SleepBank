//
//  NapSessionView.swift
//  SleepBank Watch App
//
//  The wrist UI for a nap: pick a nap type, watch the session progress through
//  its phases with a live wake countdown, and clear the alarm on wake.
//

import SwiftUI
import SleepBankCore

struct NapSessionView: View {
    @State private var nap = NapController.shared

    var body: some View {
        Group {
            if nap.isAlarming {
                alarmView
            } else if nap.isNapping {
                activeSession
            } else if let record = nap.lastCompletedNap {
                NapRecapView(record: record) { nap.dismissRecap() }
            } else {
                picker
            }
        }
        .padding()
        .onAppear { nap.requestPermissions(); consumePending() }
        .onChange(of: nap.pendingStart) { consumePending() }
    }

    /// Start a nap requested via Siri/Shortcuts once the UI is visible.
    private func consumePending() {
        guard let type = nap.pendingStart, !nap.isNapping else { return }
        nap.clearPending()
        nap.start(type: type)
    }

    // MARK: - Idle: choose a nap

    private var picker: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.indigo)

                ForEach(NapType.allCases, id: \.self) { type in
                    Button {
                        nap.start(type: type)
                    } label: {
                        VStack(spacing: 2) {
                            Text(type.title).font(.headline)
                            Text(type.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(type == .power ? .indigo : .teal)
                }

                if nap.store.countToday > 0 {
                    Text("Today: \(nap.store.countToday) nap\(nap.store.countToday == 1 ? "" : "s") · \(nap.store.minutesToday) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    NavigationLink {
                        SleepChartWatchView()
                    } label: {
                        Label("Last night", systemImage: "chart.bar.fill")
                            .font(.caption)
                    }
                    NavigationLink {
                        WatchSoundsView()
                    } label: {
                        Label("Sounds", systemImage: "speaker.wave.2.fill")
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Active session

    private var activeSession: some View {
        VStack(spacing: 8) {
            Text(nap.phaseLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(nap.countdownLabel)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(nap.onsetDetected ? "until wake" : "max remaining")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "heart.fill").foregroundStyle(.red)
                Text(nap.heartRate > 0 ? "\(nap.heartRate)" : "--").monospacedDigit()
                if nap.usingExternalHR {
                    Text("H10").font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.green.opacity(0.25), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            .font(.title3)

            ProgressView(value: nap.movementIntensity).tint(.orange)

            if nap.soundPlaying {
                HStack(spacing: 4) {
                    Image(systemName: nap.soundOutput.icon)
                    Text(nap.soundOutput.name).lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Button(role: .destructive) { nap.stop() } label: {
                Label("End", systemImage: "stop.fill")
            }
        }
    }

    // MARK: - Wake / alarm

    private var alarmView: some View {
        VStack(spacing: 14) {
            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)
            Text("Time to wake")
                .font(.headline)
            Button { nap.stop() } label: {
                Label("I'm up", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)
        }
    }
}

#Preview {
    NapSessionView()
}
