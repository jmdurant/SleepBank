//
//  LiveView.swift
//  SleepBank
//
//  The live data dashboard — the paired sensors rendered as graphs, the way the
//  sleep timeline renders Apple's data. Continuous heart rate (Polar H10), the
//  real-time EEG waveform and band powers (Muse). Mostly meaningful with sensors
//  connected (see the Sensors screen); shows gentle hints otherwise.
//

import SwiftUI
import Charts

struct LiveView: View {
    @State private var polar = PolarH10Service.shared
    @State private var muse = MuseService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heartRateCard
                eegTraceCard
                bandPowerCard
            }
            .padding()
        }
        .navigationTitle("Live")
    }

    // MARK: - Heart rate

    private var heartRateCard: some View {
        card {
            HStack {
                Label("Heart Rate", systemImage: "heart.fill").foregroundStyle(.red)
                Spacer()
                Text(polar.currentHeartRate > 0 ? "\(polar.currentHeartRate) bpm" : "—")
                    .font(.title3.monospacedDigit().bold())
            }
            if polar.heartRateHistory.count > 1 {
                Chart(polar.heartRateHistory, id: \.self) { sample in
                    LineMark(x: .value("Time", sample.timestamp),
                             y: .value("BPM", sample.bpm))
                        .foregroundStyle(.red)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: hrDomain)
                .frame(height: 140)
                if polar.hrvRMSSD > 0 {
                    Text(String(format: "HRV %.0f ms", polar.hrvRMSSD))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                placeholder("Connect the H10 in Sensors to see continuous heart rate.")
            }
        }
    }

    private var hrDomain: ClosedRange<Int> {
        let bpms = polar.heartRateHistory.map(\.bpm)
        let lo = (bpms.min() ?? 50) - 8
        let hi = (bpms.max() ?? 100) + 8
        return max(30, lo)...min(200, hi)
    }

    // MARK: - EEG trace

    private var eegTraceCard: some View {
        card {
            HStack {
                Label("EEG · AF7", systemImage: "brain.head.profile").foregroundStyle(.purple)
                Spacer()
                Text(muse.eeg.hasGoodSignal ? "Good contact" : "Poor contact")
                    .font(.caption2)
                    .foregroundStyle(muse.eeg.hasGoodSignal ? .green : .orange)
            }
            if muse.eeg.traceSamples.count > 1 {
                WaveformView(samples: muse.eeg.traceSamples, color: .purple)
                    .frame(height: 90)
                HStack(spacing: 10) {
                    eegFlag("ONSET", muse.eeg.onsetDetected, .indigo)
                    eegFlag("DEEP", muse.eeg.deepSleepApproaching, .orange)
                    Spacer()
                    Text(String(format: "onset idx %.2f", muse.eeg.onsetIndex))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                placeholder("Connect the Muse in Sensors to see the live EEG trace.")
            }
        }
    }

    private func eegFlag(_ label: String, _ on: Bool, _ color: Color) -> some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((on ? color : .gray).opacity(0.2), in: Capsule())
            .foregroundStyle(on ? color : .secondary)
    }

    // MARK: - Band powers

    private struct Band: Identifiable { let id = UUID(); let name: String; let value: Double }

    private var bands: [Band] {
        let p = muse.eeg.avgPowers
        return [
            .init(name: "Delta", value: Double(p.delta)),
            .init(name: "Theta", value: Double(p.theta)),
            .init(name: "Alpha", value: Double(p.alpha)),
            .init(name: "Sigma", value: Double(p.sigma)),
            .init(name: "Beta", value: Double(p.beta)),
            .init(name: "Gamma", value: Double(p.gamma)),
        ]
    }

    private var bandPowerCard: some View {
        card {
            Label("Brainwave bands", systemImage: "waveform.path.ecg").foregroundStyle(.purple)
            if muse.eeg.hasGoodSignal {
                Chart(bands) { band in
                    BarMark(x: .value("Band", band.name),
                            y: .value("Power", band.value))
                        .foregroundStyle(.purple.gradient)
                }
                .chartYScale(domain: 0...1)
                .frame(height: 120)
            } else {
                placeholder("Band powers appear once the Muse has good contact.")
            }
        }
    }

    // MARK: - Building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

/// A lightweight auto-scaling waveform. Centers on the window mean and scales to
/// its peak deviation, so a flat signal stays flat and an active one fills the
/// frame — Canvas keeps it cheap at EEG sample rates.
struct WaveformView: View {
    let samples: [Float]
    var color: Color = .purple

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }
            let mean = samples.reduce(0, +) / Float(samples.count)
            let maxDev = max(samples.map { abs($0 - mean) }.max() ?? 1, 1)
            let gain = Double(size.height) * 0.45 / Double(maxDev)
            let dx = size.width / Double(samples.count - 1)

            var path = Path()
            for (i, s) in samples.enumerated() {
                let x = Double(i) * dx
                let y = size.height / 2 - Double(s - mean) * gain
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }
}

#Preview {
    NavigationStack { LiveView() }
}
