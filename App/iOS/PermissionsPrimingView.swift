//
//  PermissionsPrimingView.swift
//  SleepBank
//
//  A friendly, one-screen permissions primer — the FedEx pattern. Instead of iOS
//  blasting the user with a stack of system dialogs the instant the app launches
//  (Health, Notifications, Motion, Location all at once, with no context), we show a
//  list that *explains what each permission is for* and only fires the real system
//  prompt when the user taps that row. Granted rows show a check; the rest stay open.
//
//  Shown as the last step of onboarding (WelcomeView) and re-runnable from Settings.
//  Everything here is optional — the app works without any of it (the nap timer,
//  breathing, sounds, and curve all run permission-free); each grant just makes one
//  thing sharper. Sensors (Polar H10 / Muse) ask for Bluetooth when you connect them,
//  so that one stays contextual and isn't listed here.
//

import SwiftUI
import CoreMotion
import CoreLocation
import UserNotifications

struct PermissionsPrimingView: View {
    var onDone: () -> Void

    @State private var granted: Set<Perm> = []
    @State private var busy: Perm?
    @Environment(\.scenePhase) private var scenePhase

    private let activityManager = CMMotionActivityManager()

    enum Perm: String, CaseIterable, Identifiable {
        case health, notifications, motion, location
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .health:        return "heart.text.square.fill"
            case .notifications: return "bell.badge.fill"
            case .motion:        return "figure.walk.motion"
            case .location:      return "location.fill"
            }
        }
        var title: String {
            switch self {
            case .health:        return "Apple Health"
            case .notifications: return "Notifications"
            case .motion:        return "Motion & Fitness"
            case .location:      return "Location"
            }
        }
        var detail: String {
            switch self {
            case .health:        return "Reads your sleep, heart rate, and HRV to tune your alertness curve and naps."
            case .notifications: return "Sounds your nap wake-up alarm and sends your daily alertness nudges."
            case .motion:        return "Detects when you've settled and fallen asleep — including head-stillness from AirPods."
            case .location:      return "Coarse location for your local sunrise & sunset, so light is timed to your day."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    VStack(spacing: 0) {
                        ForEach(Array(Perm.allCases.enumerated()), id: \.element) { i, perm in
                            row(perm)
                            if i < Perm.allCases.count - 1 { Divider().padding(.leading, 52) }
                        }
                    }
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                    Text("Tap each to allow it — SleepBank works without any of these, they just make it sharper. You can change them anytime in Settings.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }

            Button(action: onDone) {
                Text(granted.isEmpty ? "Skip for now" : "Continue")
                    .font(.headline).frame(maxWidth: .infinity).padding()
                    .background(.ocean.gradient, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal).padding(.bottom, 8)
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }   // catch Settings-app grants
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist").font(.system(size: 40)).foregroundStyle(.ocean)
            Text("Set up SleepBank").font(.title2.bold())
            Text("Here's what SleepBank can use, and why. Nothing turns on until you tap it.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func row(_ perm: Perm) -> some View {
        Button { request(perm) } label: {
            HStack(spacing: 12) {
                Image(systemName: perm.icon)
                    .font(.title3).foregroundStyle(.ocean).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(perm.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(perm.detail).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if busy == perm {
                    ProgressView()
                } else if granted.contains(perm) {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                } else {
                    Image(systemName: "circle").font(.title3).foregroundStyle(.tertiary)
                }
            }
            .padding()
        }
        .buttonStyle(.plain)
        .disabled(granted.contains(perm) || busy == perm)
    }

    // MARK: - Requesting

    private func request(_ perm: Perm) {
        busy = perm
        switch perm {
        case .health:
            Task {
                _ = await HealthKitService.shared.requestAuthorization()
                // HealthKit doesn't report read-grant back, so reflect that the user
                // has been through the dialog (their choice is recorded by iOS).
                granted.insert(.health); busy = nil
            }
        case .notifications:
            Task {
                await PlanNotificationService.shared.requestAndSchedule()
                await refresh(); busy = nil
            }
        case .location:
            LocationService.shared.refresh()
            // Grant comes back asynchronously via the delegate; scenePhase/refresh picks it up.
            Task { try? await Task.sleep(for: .seconds(1)); await refresh(); busy = nil }
        case .motion:
            // Any Core Motion query trips the single "Motion & Fitness" prompt that
            // also governs the AirPods head-motion we use for onset.
            guard CMMotionActivityManager.isActivityAvailable() else {
                granted.insert(.motion); busy = nil; return
            }
            let from = Calendar.current.date(byAdding: .minute, value: -1, to: Date()) ?? Date()
            activityManager.queryActivityStarting(from: from, to: Date(), to: .main) { _, _ in
                Task { await refresh() }
                busy = nil
            }
        }
    }

    // MARK: - Status

    private func refresh() async {
        var g = granted   // keep health (not readable back) sticky once handled

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            g.insert(.notifications)
        }
        if CMMotionActivityManager.authorizationStatus() == .authorized {
            g.insert(.motion)
        }
        if LocationService.shared.isAuthorized {
            g.insert(.location)
        }
        if HealthKitService.shared.isAuthorized {
            g.insert(.health)
        }
        granted = g
    }
}

#Preview {
    NavigationStack { PermissionsPrimingView(onDone: {}) }
}
