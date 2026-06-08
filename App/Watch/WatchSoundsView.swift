//
//  WatchSoundsView.swift
//  SleepBank Watch App
//
//  On-wrist control for phone-free naps: pick a noise colour, set volume, and
//  toggle whether the watch itself plays a relaxing sound during a nap (it fades
//  out once you fall asleep). Use this when the phone isn't nearby.
//

import SwiftUI

struct WatchSoundsView: View {
    @State private var noise = NoiseService.shared

    var body: some View {
        List {
            Section("Play on watch") {
                Toggle("During naps", isOn: Binding(
                    get: { noise.autoPlayDuringNap },
                    set: { noise.autoPlayDuringNap = $0 }
                ))
            }

            Section("Sound") {
                ForEach(NoiseColor.allCases) { color in
                    Button {
                        noise.play(color)   // select + preview
                    } label: {
                        HStack {
                            Text(color.title)
                            Spacer()
                            if noise.color == color {
                                Image(systemName: "checkmark").foregroundStyle(.indigo)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }

            Section("Volume") {
                Slider(value: $noise.volume, in: 0...1)
            }

            Section {
                Label(noise.currentOutput.name, systemImage: noise.currentOutput.icon)
            } header: {
                Text("Output")
            } footer: {
                Text("Plays through AirPods when connected, otherwise the watch speaker. Use the Now Playing controls to switch output.")
            }

            if noise.isPlaying {
                Button(role: .destructive) { noise.stop() } label: {
                    Label("Stop preview", systemImage: "stop.fill")
                }
            }
        }
        .navigationTitle("Sounds")
    }
}

#Preview {
    NavigationStack { WatchSoundsView() }
}
