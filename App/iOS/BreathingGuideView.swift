//
//  BreathingGuideView.swift
//  SleepBank
//
//  A visual, haptic-paced breathing guide. Before you begin, a soft orb sits centered
//  with the 4-7-8 explanation. On Begin, a calming beach fades in and the orb glides up
//  to the sun (day) / moon (night) position in the sky — recolored sun-yellow / moon-
//  white — and breathes there: expanding on the inhale, holding, contracting on the
//  exhale, with a haptic at each phase. The cycle count moves to the top-left.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct BreathingGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var pacer = BreathingPacer.shared
    private let totalCycles = 8
    @AppStorage(BreathingHaptics.intensityKey) private var hapticIntensity = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.10, green: 0.09, blue: 0.22), .black],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                BeachSceneView()
                    .opacity(pacer.isRunning ? 1 : 0)
                    .animation(.easeInOut(duration: 3), value: pacer.isRunning)
                    .allowsHitTesting(false)

                // Keep text/controls legible over a bright daytime sky.
                LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // The breathing orb — stays centered; rises to the sky height as the
                // sun/moon when you begin.
                orb
                    .position(x: geo.size.width * 0.5,
                              y: geo.size.height * (pacer.isRunning ? 0.26 : 0.40))
                    .animation(.easeInOut(duration: 1.6), value: pacer.isRunning)

                if pacer.isRunning {
                    Text("Cycle \(pacer.cycle) of \(totalCycles)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.3), radius: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(24)
                        .allowsHitTesting(false)

                    Text(pacer.phase.label)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                        .shadow(color: .black.opacity(0.4), radius: 8)
                }

                VStack(spacing: 16) {
                    Spacer()
                    if pacer.isRunning {
                        Button { pacer.stop() } label: {
                            Label("Stop", systemImage: "stop.fill").font(.headline)
                                .frame(maxWidth: .infinity).padding()
                                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("4-7-8 breathing")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))
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
                    vibrationControl
                }
                .padding(28)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { pacer.stop(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.6))
            }
            .padding()
        }
        .onDisappear { pacer.stop() }
    }

    // MARK: - Orb (becomes the sun / moon)

    private var orb: some View {
        let size: CGFloat = pacer.isRunning ? 150 : 240
        return Circle()
            .fill(orbShading)
            .frame(width: size, height: size)
            .scaleEffect(pacer.phase.targetScale)
            .shadow(color: glowColor, radius: pacer.isRunning ? 38 : 40)
            .animation(.easeInOut(duration: max(0.3, pacer.phase.seconds)), value: pacer.phase)
    }

    private var orbShading: AnyShapeStyle {
        guard pacer.isRunning else {
            return AnyShapeStyle(.radialGradient(Gradient(colors: [.purple.opacity(0.85), .indigo.opacity(0.25)]),
                                                 center: .center, startRadius: 10, endRadius: 150))
        }
        let colors: [Color] = scheme == .dark
            ? [Color(white: 0.98), Color(red: 0.92, green: 0.92, blue: 0.82)]                  // moon white
            : [Color(red: 1, green: 0.97, blue: 0.72), Color(red: 1, green: 0.82, blue: 0.34)]  // sun yellow
        return AnyShapeStyle(.radialGradient(Gradient(colors: colors),
                                             center: .center, startRadius: 4, endRadius: 78))
    }

    private var glowColor: Color {
        guard pacer.isRunning else { return .purple.opacity(0.5) }
        return scheme == .dark ? Color.white.opacity(0.5) : Color(red: 1, green: 0.85, blue: 0.4).opacity(0.6)
    }

    /// Baseline vibration strength — turn it up to feel the taps over real-world
    /// vibration (e.g. napping in a car). Persists; a sample tap plays as you drag.
    private var vibrationControl: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Vibration strength").font(.caption.weight(.medium))
                Spacer()
                Text(hapticIntensity < 0.9 ? "Gentle" : (hapticIntensity > 1.4 ? "Strong" : "Normal"))
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.caption2)
                Slider(value: $hapticIntensity, in: 0.5...2.0, step: 0.1)
                    .tint(.ocean)
                    .onChange(of: hapticIntensity) { _, _ in BreathingHaptics.shared.previewTap() }
                Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.body)
            }
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 4)
    }
}
