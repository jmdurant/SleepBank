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
    @State private var relax = GuidedRelaxationService.shared
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

            Section {
                Slider(value: $noise.volume, in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
                }
                LabeledContent("Level", value: "\(Int(noise.volume * 100))%")
            } header: {
                Text("Volume")
            } footer: {
                Text("Build check: a fresh install starts at 30%. If this opens at 60%, you're on an old build — force-quit and reopen.")
            }

            Section {
                Toggle("Play during naps", isOn: Binding(
                    get: { noise.autoPlayDuringNap },
                    set: { noise.autoPlayDuringNap = $0 }
                ))
            } footer: {
                Text("Starts the selected sound when a nap begins and fades it out as you wake.")
            }

            Section {
                Picker("Spoken guide", selection: Binding(
                    get: { relax.guide },
                    set: { relax.guide = $0 }
                )) {
                    ForEach(RelaxationGuide.allCases) { Text($0.title).tag($0) }
                }
                if relax.guide != .none {
                    Toggle("Play guide during naps", isOn: Binding(
                        get: { relax.autoPlayDuringNap },
                        set: { relax.autoPlayDuringNap = $0 }
                    ))
                    Button(relax.isSpeaking ? "Stop preview" : "Preview guide") {
                        relax.isSpeaking ? relax.stop() : relax.start(relax.guide)
                    }
                }
            } header: {
                Text("Wind-down guide")
            } footer: {
                Text("A spoken relaxation that plays as you settle and stops once you're asleep. Layers over the sound.")
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
