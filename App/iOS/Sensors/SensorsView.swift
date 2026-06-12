//
//  SensorsView.swift
//  SleepBank
//
//  One place to connect *and* watch the paired sensors that enrich nap detection:
//  the Muse headband (EEG) and the Polar H10 (continuous HR + HRV). Each sensor's
//  section shows connection/streaming status, a connect/disconnect control, and its
//  live data (graphs) once it's streaming — merged from the old separate Live screen.
//

import SwiftUI
import Charts

struct SensorsView: View {
    @State private var muse = MuseService.shared
    @State private var polar = PolarH10Service.shared
    @State private var airpods = PhoneWorkoutHRService.shared
    @State private var airpodsMotion = AirPodsMotionService.shared
    @State private var watch = WatchHRService.shared
    @State private var checking = false        // this screen opened the AirPods session
    @State private var checkingWatch = false   // this screen requested the watch relay

    var body: some View {
        List {
            museSection
            polarSection
            watchSection
            airpodsSection
        }
        .navigationTitle("Sensors")
        .onDisappear {
            // Close anything we opened — unless a nap now owns it.
            if !PhoneNapController.shared.isNapping {
                if checking { airpods.stop(); airpodsMotion.stop() }
                if checkingWatch { watch.requestStop() }
            }
            checking = false; checkingWatch = false
        }
    }

    // MARK: - Apple Watch (wrist HR relayed over to the phone)

    private var watchSection: some View {
        Section {
            let napActive = PhoneNapController.shared.isNapping
            sensorHeader(
                name: watch.isStreaming ? "Reading heart rate" : (watch.requested ? "Waiting for watch…" : "Off"),
                connected: watch.requested,
                streaming: watch.isStreaming,
                detail: napActive ? "Active during your nap" : "Wear your Apple Watch (app open), then Check",
                buttonTitle: napActive ? nil : (watch.requested ? "Stop" : "Check")
            ) {
                if watch.requested { watch.requestStop(); checkingWatch = false }
                else { watch.requestStart(); checkingWatch = true }
            }
            if let hr = watch.freshHeartRate {
                LabeledContent("Heart rate", value: "\(hr) bpm")
            }
            if let mv = watch.freshMovement {
                LabeledContent("Wrist movement", value: String(format: "%.0f%%", mv * 100))
            }
            if napActive {
                Text("Your nap is requesting wrist heart rate from the watch.").font(.caption2).foregroundStyle(.secondary)
            }
            if watch.heartRateHistory.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Heart rate", systemImage: "heart.fill").font(.caption).foregroundStyle(.red)
                    Chart(watch.heartRateHistory, id: \.self) { sample in
                        LineMark(x: .value("Time", sample.timestamp), y: .value("BPM", sample.bpm))
                            .foregroundStyle(.red).interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: hrDomain(watch.heartRateHistory)).frame(height: 120)
                }
            }
        } header: {
            Text("Apple Watch — Heart rate")
        } footer: {
            Text("Needs the SleepBank watch app open/reachable — the phone can't wake it. It runs a brief workout to read wrist HR (discarded, not saved).")
        }
    }

    // MARK: - Muse (connect + live EEG)

    private var museSection: some View {
        Section("Muse — EEG") {
            sensorHeader(
                name: muse.deviceName ?? (muse.isScanning ? "Scanning…" : "Not connected"),
                connected: muse.isConnected,
                streaming: muse.isStreaming,
                detail: muse.isConnected ? (muse.eeg.hasGoodSignal ? "Good contact" : "Adjust fit") : nil,
                buttonTitle: muse.isConnected ? "Disconnect" : "Connect"
            ) { muse.isConnected ? muse.disconnect() : muse.startScanning() }
            NavigationLink("EEG detail") { MuseMonitorView(muse: muse) }

            if muse.eeg.traceSamples.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("AF7 trace", systemImage: "brain.head.profile").font(.caption).foregroundStyle(.ocean)
                        Spacer()
                        Text(muse.eeg.hasGoodSignal ? "Good contact" : "Poor contact")
                            .font(.caption2).foregroundStyle(muse.eeg.hasGoodSignal ? .green : .sand)
                    }
                    WaveformView(samples: muse.eeg.traceSamples, color: .ocean).frame(height: 80)
                    HStack(spacing: 10) {
                        eegFlag("ONSET", muse.eeg.onsetDetected, .ocean)
                        eegFlag("DEEP", muse.eeg.deepSleepApproaching, .sand)
                        Spacer()
                        Text(String(format: "onset idx %.2f", muse.eeg.onsetIndex))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if muse.eeg.hasGoodSignal {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Brainwave bands", systemImage: "waveform.path.ecg").font(.caption).foregroundStyle(.ocean)
                    Chart(bands) { band in
                        BarMark(x: .value("Band", band.name), y: .value("Power", band.value))
                            .foregroundStyle(.ocean.gradient)
                    }
                    .chartYScale(domain: 0...1).frame(height: 110)
                }
            }
        }
    }

    // MARK: - Polar H10 (connect + live HR)

    private var polarSection: some View {
        Section("Polar H10 — Heart rate") {
            sensorHeader(
                name: polar.deviceName ?? "Not connected",
                connected: polar.isConnected,
                streaming: polar.isStreaming,
                detail: polar.batteryLevel >= 0 ? "Battery \(polar.batteryLevel)%" : nil,
                buttonTitle: polar.isConnected ? "Disconnect" : "Connect"
            ) { polar.isConnected ? polar.disconnect() : polar.autoConnect() }
            if polar.isStreaming {
                LabeledContent("Heart rate", value: polar.currentHeartRate > 0 ? "\(polar.currentHeartRate) bpm" : "—")
                LabeledContent("HRV (RMSSD)", value: polar.hrvRMSSD > 0 ? String(format: "%.0f ms", polar.hrvRMSSD) : "—")
                LabeledContent("Breathing", value: polar.breathingRate > 0 ? String(format: "%.0f br/min", polar.breathingRate) : "—")
                LabeledContent("Movement", value: polar.isAccStreaming ? String(format: "%.0f%%", polar.movementIntensity * 100) : "—")
                if polar.isAccStreaming {
                    LabeledContent("Posture", value: polar.posture)
                    LabeledContent("Orientation",
                        value: String(format: "x %.2f  y %.2f  z %.2f", polar.accelX, polar.accelY, polar.accelZ))
                }
            }
            if let err = polar.lastStreamError {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
            if polar.heartRateHistory.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Heart rate", systemImage: "heart.fill").font(.caption).foregroundStyle(.red)
                    Chart(polar.heartRateHistory, id: \.self) { sample in
                        LineMark(x: .value("Time", sample.timestamp), y: .value("BPM", sample.bpm))
                            .foregroundStyle(.red).interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: hrDomain(polar.heartRateHistory)).frame(height: 120)
                }
            }
        }
    }

    // MARK: - AirPods Pro (on-demand HR via a workout session)

    private var airpodsSection: some View {
        Section {
            let napActive = PhoneNapController.shared.isNapping
            sensorHeader(
                name: airpods.isActive ? "Reading heart rate" : "Off",
                connected: airpods.isActive,
                streaming: airpods.freshHeartRate != nil,
                detail: napActive ? "Active during your nap"
                                  : (airpods.isActive ? "Keep AirPods Pro in" : "Put AirPods Pro in, then Check"),
                buttonTitle: napActive ? nil : (airpods.isActive ? "Stop" : "Check")
            ) {
                if airpods.isActive { airpods.stop(); airpodsMotion.stop(); checking = false }
                else { airpods.start(); airpodsMotion.start(); checking = true }
            }
            if airpods.isActive {
                LabeledContent("Heart rate", value: airpods.freshHeartRate.map { "\($0) bpm" } ?? "waiting…")
            }
            if let hm = airpodsMotion.freshMovement {
                LabeledContent("Head movement", value: String(format: "%.0f%%", hm * 100))
            }
            if napActive {
                Text("Your nap session is reading heart rate and head stillness.").font(.caption2).foregroundStyle(.secondary)
            }
            if airpods.heartRateHistory.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Heart rate", systemImage: "heart.fill").font(.caption).foregroundStyle(.red)
                    Chart(airpods.heartRateHistory, id: \.self) { sample in
                        LineMark(x: .value("Time", sample.timestamp), y: .value("BPM", sample.bpm))
                            .foregroundStyle(.red).interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: hrDomain(airpods.heartRateHistory)).frame(height: 120)
                }
            }
        } header: {
            Text("AirPods Pro — Heart rate")
        } footer: {
            Text("AirPods Pro stream heart rate only during a workout session — we open one to read it (and discard it, so nothing is saved).")
        }
    }

    // MARK: - Helpers

    /// One combined header row per sensor — status dot + name/detail + the connect
    /// control on a single line, instead of three stacked rows.
    private func sensorHeader(name: String, connected: Bool, streaming: Bool,
                              detail: String?, buttonTitle: String?,
                              action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(streaming ? .green : (connected ? .sand : .gray))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered).controlSize(.small)
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

    private func hrDomain(_ history: [HeartRateSample]) -> ClosedRange<Int> {
        let bpms = history.map(\.bpm)
        let lo = (bpms.min() ?? 50) - 8
        let hi = (bpms.max() ?? 100) + 8
        return max(30, lo)...min(200, hi)
    }
}

/// A lightweight auto-scaling waveform. Centers on the window mean and scales to its
/// peak deviation, so a flat signal stays flat and an active one fills the frame.
struct WaveformView: View {
    let samples: [Float]
    var color: Color = .ocean

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
    NavigationStack { SensorsView() }
}
