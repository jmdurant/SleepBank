//
//  SoundsView.swift
//  SleepBank
//
//  Pick and play a relaxing sound to fall asleep to, and choose whether it should
//  start automatically when a nap begins (it fades out at wake).
//

import SwiftUI
import AVFoundation

struct SoundsView: View {
    @State private var noise = NoiseService.shared
    @State private var routeTick = 0   // bumps to refresh the output label

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: noise.currentOutput.icon).foregroundStyle(.indigo)
                    Text(noise.currentOutput.name).id(routeTick)
                    Spacer()
                    RoutePickerView().frame(width: 40, height: 40)
                }
            } header: {
                Text("Output")
            } footer: {
                Text("Tap the AirPlay icon to send the sound to AirPods, a speaker, or another AirPlay device.")
            }

            Section("Sound") {
                ForEach(NoiseColor.allCases) { color in
                    Button {
                        if noise.isPlaying && noise.color == color {
                            noise.stop()
                        } else {
                            noise.play(color)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(color.title)
                                Text(color.subtitle).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if noise.isPlaying && noise.color == color {
                                Image(systemName: "waveform").foregroundStyle(.indigo)
                                    .symbolEffect(.variableColor.iterative)
                            } else {
                                Image(systemName: "play.circle").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }

            Section("Volume") {
                Slider(value: $noise.volume, in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Play during naps", isOn: Binding(
                    get: { noise.autoPlayDuringNap },
                    set: { noise.autoPlayDuringNap = $0 }
                ))
            } footer: {
                Text("Starts the selected sound when a nap begins and fades it out as you wake.")
            }

            if noise.isPlaying {
                Section {
                    Button(role: .destructive) { noise.stop() } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
            }
        }
        .navigationTitle("Sounds")
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            routeTick += 1
        }
    }
}

#Preview {
    NavigationStack { SoundsView() }
}
