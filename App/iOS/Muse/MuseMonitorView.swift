//
//  MuseMonitorView.swift
//  SleepBank
//
//  A live read-out of the Muse EEG pipeline for n=1 validation: connect the
//  headband, confirm contact quality, and watch the sleep-relevant signals
//  (onset index, band powers, delta/deep-sleep approach) in real time. This is a
//  research/debug surface — the place to compare what the EEG says against what
//  the watch-only detector decides, before fusing them.
//

import SwiftUI

struct MuseMonitorView: View {
    @Bindable var muse: MuseService

    var body: some View {
        List {
            Section("Headband") {
                HStack {
                    Text(muse.deviceName ?? (muse.isScanning ? "Scanning…" : "Not connected"))
                    Spacer()
                    statusDot
                }
                Button(muse.isConnected ? "Disconnect" : "Connect Muse") {
                    muse.isConnected ? muse.disconnect() : muse.startScanning()
                }
            }

            Section("Signal quality") {
                ForEach(Array(["TP9", "AF7", "AF8", "TP10"].enumerated()), id: \.offset) { i, name in
                    qualityRow(name, muse.eeg.channelQuality[i])
                }
                Label(muse.eeg.hasGoodSignal ? "Good contact" : "Poor contact",
                      systemImage: muse.eeg.hasGoodSignal ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(muse.eeg.hasGoodSignal ? .green : .orange)
            }

            Section {
                ForEach(Array(["TP9", "AF7", "AF8", "TP10"].enumerated()), id: \.offset) { i, name in
                    HStack {
                        Text(name).frame(width: 50, alignment: .leading)
                        Spacer()
                        Text("mean \(Int(muse.eeg.channelMean[i]))  ·  range \(Int(muse.eeg.channelRange[i]))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Raw diagnostics (12-bit)")
            } footer: {
                Text("Good contact ≈ mean near 2048, range a few hundred. Mean pinned near 0/4095 or a flat range means the electrode isn't reading skin.")
            }

            Section("Sleep signals") {
                metric("Onset index", muse.eeg.onsetIndex,
                       flag: muse.eeg.onsetDetected ? "ONSET" : nil, flagColor: .indigo)
                metric("Delta (deep)", muse.eeg.deltaDominance,
                       flag: muse.eeg.deepSleepApproaching ? "WAKE" : nil, flagColor: .orange)
                metric("Spindle (N2)", muse.eeg.spindlePower)
            }

            Section("Band powers") {
                bandRow("Delta", muse.eeg.avgPowers.delta)
                bandRow("Theta", muse.eeg.avgPowers.theta)
                bandRow("Alpha", muse.eeg.avgPowers.alpha)
                bandRow("Sigma", muse.eeg.avgPowers.sigma)
                bandRow("Beta", muse.eeg.avgPowers.beta)
                bandRow("Gamma", muse.eeg.avgPowers.gamma)
            }
        }
        .navigationTitle("Muse EEG")
    }

    private var statusDot: some View {
        Circle()
            .fill(muse.isStreaming ? .green : (muse.isConnected ? .yellow : .gray))
            .frame(width: 10, height: 10)
    }

    private func qualityRow(_ name: String, _ q: Float) -> some View {
        HStack {
            Text(name).frame(width: 50, alignment: .leading)
            ProgressView(value: Double(q)).tint(q > 0.5 ? .green : .orange)
            Text("\(Int(q * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }

    private func metric(_ label: String, _ value: Float, flag: String? = nil, flagColor: Color = .secondary) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let flag {
                Text(flag).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(flagColor.opacity(0.2), in: Capsule()).foregroundStyle(flagColor)
            }
            Text(String(format: "%.2f", value)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func bandRow(_ name: String, _ value: Float) -> some View {
        HStack {
            Text(name).frame(width: 60, alignment: .leading)
            ProgressView(value: Double(min(1, value))).tint(.purple)
            Text(String(format: "%.0f%%", value * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}

#Preview {
    NavigationStack { MuseMonitorView(muse: MuseService()) }
}
