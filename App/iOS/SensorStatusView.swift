//
//  SensorStatusView.swift
//  SleepBank
//
//  A compact, tappable card for the home screen: shows which sensors are in use and
//  their live readouts at a glance (heart rate from whichever source, EEG contact),
//  and opens the full Sensors page. Always present, so it doubles as the quick way to
//  connect/check sensors.
//

import SwiftUI

struct SensorStatusView: View {
    @State private var muse = MuseService.shared
    @State private var polar = PolarH10Service.shared
    @State private var airpods = PhoneWorkoutHRService.shared
    @State private var watch = WatchHRService.shared

    var body: some View {
        // Refresh every few seconds so the live values + freshness stay current.
        TimelineView(.periodic(from: .now, by: 3)) { _ in
            NavigationLink { SensorsView() } label: { card }
                .buttonStyle(.plain)
        }
    }

    private var card: some View {
        HStack(spacing: 12) {
            Image(systemName: "sensor.tag.radiowaves.forward").font(.title3).foregroundStyle(.ocean)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sensors").font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let (hr, src) = liveHR {
                VStack(spacing: 0) {
                    Label("\(hr)", systemImage: "heart.fill")
                        .font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(.red)
                    Text(src).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if muse.isConnected {
                Image(systemName: "brain.head.profile")
                    .font(.subheadline).foregroundStyle(muse.eeg.hasGoodSignal ? .green : .sand)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var connected: [String] {
        var s: [String] = []
        if polar.isConnected { s.append("H10") }
        if muse.isConnected { s.append("Muse") }
        if watch.isStreaming { s.append("Watch") }
        if airpods.isActive { s.append("AirPods") }
        return s
    }

    private var subtitle: String {
        connected.isEmpty ? "Tap to connect a sensor" : connected.joined(separator: " · ")
    }

    /// The live heart rate to surface, by source priority.
    private var liveHR: (Int, String)? {
        if polar.currentHeartRate > 0 { return (polar.currentHeartRate, "H10") }
        if let w = watch.freshHeartRate { return (w, "Watch") }
        if let a = airpods.freshHeartRate { return (a, "AirPods") }
        return nil
    }
}
