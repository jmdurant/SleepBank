//
//  BreathingGuideView.swift
//  SleepBank
//
//  A visual, haptic-paced breathing guide — the Apple-Watch-Breathe approach rather
//  than a chatty robotic voice. The circle expands on the inhale, holds, and contracts
//  on the exhale, with a soft haptic at each phase change, on precise timers (so the
//  cadence is exact, unlike TTS). We explain the 4-7-8 pattern, then let you follow.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct BreathingGuideView: View {
    @Environment(\.dismiss) private var dismiss
    private var pacer = BreathingPacer.shared
    private let totalCycles = 8

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.09, blue: 0.22), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Text(pacer.isRunning ? "Cycle \(pacer.cycle) of \(totalCycles)" : "4-7-8 breathing")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.65))

                ZStack {
                    Circle()
                        .fill(.radialGradient(colors: [.purple.opacity(0.85), .indigo.opacity(0.25)],
                                              center: .center, startRadius: 10, endRadius: 150))
                        .frame(width: 240, height: 240)
                        .scaleEffect(pacer.phase.targetScale)
                        .shadow(color: .purple.opacity(0.5), radius: 40)
                        .animation(.easeInOut(duration: max(0.3, pacer.phase.seconds)), value: pacer.phase)
                    Text(pacer.phase.label)
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .contentTransition(.opacity)
                }
                .frame(height: 300)

                if pacer.isRunning {
                    Button { pacer.stop() } label: {
                        Label("Stop", systemImage: "stop.fill").font(.headline)
                            .frame(maxWidth: .infinity).padding()
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Breathe in for 4, hold for 7, breathe out for 8. Follow the circle and the gentle taps — no need to count.")
                        .font(.callout).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button { pacer.start(cycles: totalCycles) } label: {
                        Label("Begin", systemImage: "wind").font(.headline)
                            .frame(maxWidth: .infinity).padding()
                            .background(.purple.gradient, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
        }
        .overlay(alignment: .topTrailing) {
            Button { pacer.stop(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.6))
            }
            .padding()
        }
        .onDisappear { pacer.stop() }
    }
}
