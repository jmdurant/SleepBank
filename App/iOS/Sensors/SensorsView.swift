//
//  SensorsView.swift
//  SleepBank
//
//  One place to connect and check the paired sensors that enrich nap detection:
//  the Muse headband (EEG) and the Polar H10 (continuous HR + HRV). Shows live
//  connection/streaming status for each, with a connect/disconnect control and a
//  drill-in to the Muse EEG detail.
//

import SwiftUI

struct SensorsView: View {
    @State private var muse = MuseService()
    @State private var polar = PolarH10Service.shared

    var body: some View {
        List {
            museSection
            polarSection
        }
        .navigationTitle("Sensors")
    }

    // MARK: - Muse

    private var museSection: some View {
        Section("Muse — EEG") {
            statusRow(
                name: muse.deviceName ?? (muse.isScanning ? "Scanning…" : "Not connected"),
                connected: muse.isConnected,
                streaming: muse.isStreaming,
                detail: muse.isConnected ? (muse.eeg.hasGoodSignal ? "Good contact" : "Adjust fit") : nil
            )
            Button(muse.isConnected ? "Disconnect" : "Connect Muse") {
                muse.isConnected ? muse.disconnect() : muse.startScanning()
            }
            NavigationLink("EEG detail") { MuseMonitorView(muse: muse) }
        }
    }

    // MARK: - Polar H10

    private var polarSection: some View {
        Section("Polar H10 — Heart rate") {
            statusRow(
                name: polar.deviceName ?? "Not connected",
                connected: polar.isConnected,
                streaming: polar.isStreaming,
                detail: polar.batteryLevel >= 0 ? "Battery \(polar.batteryLevel)%" : nil
            )
            if polar.isStreaming {
                LabeledContent("Heart rate", value: polar.currentHeartRate > 0 ? "\(polar.currentHeartRate) bpm" : "—")
                LabeledContent("HRV (RMSSD)", value: polar.hrvRMSSD > 0 ? String(format: "%.0f ms", polar.hrvRMSSD) : "—")
            }
            Button(polar.isConnected ? "Disconnect" : "Connect H10") {
                polar.isConnected ? polar.disconnect() : polar.autoConnect()
            }
            if let err = polar.lastStreamError {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Shared row

    private func statusRow(name: String, connected: Bool, streaming: Bool, detail: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Circle()
                .fill(streaming ? .green : (connected ? .yellow : .gray))
                .frame(width: 10, height: 10)
        }
    }
}

#Preview {
    NavigationStack { SensorsView() }
}
