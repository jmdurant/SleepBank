//
//  NapView.swift
//  SleepBank
//
//  Start and run a nap from the phone — the at-home mode. Mirrors the watch nap
//  UI: pick a type, watch it progress with a live wake countdown and the paired
//  sensors, clear the alarm on wake, see a recap.
//

import SwiftUI
import AVFoundation
import SleepChartKit
import SleepBankCore

struct NapView: View {
    @State private var nap = PhoneNapController.shared
    @State private var kss = KSSStore.shared
    @State private var routeTick = 0   // bumps to refresh the output label on route change
    @AppStorage("napTrackAlertness") private var trackAlertness = false
    @State private var showKSSPre = false
    @State private var showKSSPost = false
    @State private var pendingNapType: NapType?
    @State private var ratedSession: KSSSession?
    @State private var showBreathe = false
    @State private var breathedThisNap = false

    var body: some View {
        Group {
            if nap.isAlarming {
                alarmView
            } else if nap.isNapping {
                activeSession
            } else if let record = nap.lastCompletedNap {
                recap(record)
            } else {
                picker
            }
        }
        .padding(.horizontal)
        // Settle into the nap with the same visual 4-7-8 guide as Wind Down — shown
        // automatically when the nap starts (unless the spoken body-scan is selected),
        // and reopenable from the active screen. Dismiss to drop to the timer.
        .fullScreenCover(isPresented: $showBreathe) { BreathingGuideView() }
        .onChange(of: nap.isNapping) { _, napping in
            if napping {
                if !breathedThisNap && GuidedRelaxationService.shared.guide != .eyeRelaxation {
                    breathedThisNap = true
                    showBreathe = true
                }
            } else {
                breathedThisNap = false
            }
        }
        // Before the nap: rate sleepiness, then start (Skip starts it anyway).
        .sheet(isPresented: $showKSSPre, onDismiss: {
            if let t = pendingNapType { nap.start(type: t); pendingNapType = nil }
        }) {
            KSSPickerView(title: "Before your nap",
                          prompt: "How sleepy do you feel right now?") { value in
                kss.startSession(pre: value)
                showKSSPre = false
            }
        }
        // At the recap: rate it again to see the change.
        .sheet(isPresented: $showKSSPost) {
            KSSPickerView(title: "Now you're up",
                          prompt: "How sleepy do you feel now?") { value in
                kss.completeOpenSession(post: value)
                ratedSession = kss.latest
                showKSSPost = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            routeTick += 1
        }
    }

    private func startNap(_ type: NapType) {
        ratedSession = nil
        if trackAlertness {
            pendingNapType = type
            showKSSPre = true
        } else {
            nap.start(type: type)
        }
    }

    // MARK: - Pick a nap

    private var picker: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 44)).foregroundStyle(.ocean)
            ForEach(NapType.allCases, id: \.self) { type in
                Button {
                    startNap(type)
                } label: {
                    VStack(spacing: 2) {
                        Text(type.title).font(.headline)
                        Text(type.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(type == .power ? .ocean : .teal)
            }

            Toggle(isOn: $trackAlertness) {
                Label("Rate alertness before & after", systemImage: "bolt.fill")
                    .font(.caption)
            }
            .tint(.ocean)
            .padding(.horizontal, 4)

            Text("Uses the paired Polar H10 and Muse when connected. Open Sensors to connect them.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    // MARK: - Active

    private var activeSession: some View {
        VStack(spacing: 14) {
            Text(nap.phaseLabel).font(.subheadline).foregroundStyle(.secondary)
            Text(nap.countdownLabel)
                .font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(nap.onsetDetected ? "until wake" : "max remaining")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 18) {
                stat("heart.fill", .red, nap.heartRate > 0 ? "\(nap.heartRate)" : "--", "bpm")
                stat("waveform.path.ecg", .pink, nap.hrv > 0 ? String(format: "%.0f", nap.hrv) : "--", "HRV")
                stat("lungs.fill", .teal, nap.breathingRate > 0 ? String(format: "%.0f", nap.breathingRate) : "--", "br/min")
                stat("brain.head.profile", nap.museGood ? .ocean : .gray,
                     nap.museGood ? "EEG" : "—", nap.museGood ? "good" : "no sig")
            }
            if nap.spo2 > 0 {
                Label(String(format: "SpO₂ %.0f%%", nap.spo2), systemImage: "drop.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Group {
                if let err = LiveActivityManager.shared.lastError {
                    Text("Live Activity: \(err)")
                } else if LiveActivityManager.shared.enabled {
                    Text("Live Activity active — see it on the Lock Screen / Dynamic Island")
                } else {
                    Text("Live Activities are off in Settings → SleepBank")
                }
            }
            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Image(systemName: NoiseService.shared.currentOutput.icon).font(.caption).foregroundStyle(.ocean)
                Text(NoiseService.shared.currentOutput.name).font(.caption).foregroundStyle(.secondary).id(routeTick)
                Spacer()
                RoutePickerView().frame(width: 34, height: 34)
            }
            .padding(.horizontal, 4)

            Label("Turn on a Focus (or Do Not Disturb) so nothing interrupts you — your wake alarm still sounds through it.",
                  systemImage: "moon.fill")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Button { showBreathe = true } label: {
                Label("Breathe with the circle", systemImage: "wind")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color.ocean.opacity(0.15), in: Capsule())
                    .foregroundStyle(.ocean)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            HStack(spacing: 12) {
                Button { nap.cancel() } label: {
                    Label("Cancel", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button(role: .destructive) { nap.stop() } label: {
                    Label("End nap", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func stat(_ icon: String, _ color: Color, _ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title3.monospacedDigit().bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Alarm

    private var alarmView: some View {
        VStack(spacing: 18) {
            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.system(size: 60)).foregroundStyle(.sand).symbolEffect(.pulse)
            Text("Time to wake").font(.title2.bold())
            Button { nap.stop() } label: {
                Label("I'm up", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(.green)
        }
    }

    // MARK: - Recap

    private func recap(_ record: NapRecord) -> some View {
        VStack(spacing: 14) {
            Text("Nap complete").font(.title3.bold())
            SleepChartView(samples: NapChart.samples(from: record), style: .timeline)
                .frame(height: 120)
            if record.onset != nil {
                Text("\(Int(record.asleepDuration / 60)) min asleep").font(.headline)
                if let lat = NapChart.onsetLatencyMinutes(record) {
                    Text("Fell asleep in \(lat) min").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Didn't detect sleep this time").font(.subheadline).foregroundStyle(.secondary)
            }

            if let s = ratedSession, let delta = s.delta, let post = s.post {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").foregroundStyle(delta < 0 ? .green : .sand)
                        Text("Sleepiness \(s.pre) → \(post)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    Text(delta < 0 ? "More alert than before your nap." :
                            (delta > 0 ? "A bit groggy — give it a few minutes to lift."
                                       : "About the same right now."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if kss.hasOpenSession {
                Button { showKSSPost = true } label: {
                    Label("Rate how alert you feel now", systemImage: "bolt.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered).tint(.ocean)
            }

            Button { ratedSession = nil; kss.cancelOpenSession(); nap.dismissRecap() } label: {
                Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(.ocean)
        }
    }
}

#Preview {
    NavigationStack { NapView() }
}
