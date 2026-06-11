//
//  WindDownView.swift
//  SleepBank
//
//  The evening mirror of the daytime alertness manager: bring alertness *down* to
//  protect sleep. Evening light/screens are the strongest lever keeping it up (the
//  most robust light finding in DAYLIGHT_EVIDENCE.md), so this guides dimming +
//  screens-off + a consistent bedtime, offers a one-tap relaxation wind-down, and
//  tracks a self-reported "screens off" streak (iOS won't let us read Screen Time).
//

import SwiftUI
import SleepBankCore

/// Self-reported "screens off" nights (iOS blocks third-party Screen Time access),
/// persisted locally; streak via SleepBankCore.
enum WindDownLog {
    private static let key = "windDownScreensOffDays"

    private static var days: Set<Date> {
        get { Set((UserDefaults.standard.array(forKey: key) as? [Double] ?? []).map { Date(timeIntervalSinceReferenceDate: $0) }) }
        set { UserDefaults.standard.set(newValue.map { $0.timeIntervalSinceReferenceDate }, forKey: key) }
    }

    static func isMarked(_ date: Date = Date()) -> Bool {
        let cal = Calendar.current
        return days.contains { cal.isDate($0, inSameDayAs: date) }
    }

    static func mark(_ on: Bool, date: Date = Date()) {
        let cal = Calendar.current
        var s = days.filter { !cal.isDate($0, inSameDayAs: date) }
        if on { s.insert(cal.startOfDay(for: date)) }
        days = s
    }

    static var streak: Int { Streaks.consecutiveDays(days, asOf: Date()) }
}

struct WindDownView: View {
    @State private var health = HealthKitService.shared
    @State private var noise = NoiseService.shared
    @State private var relax = GuidedRelaxationService.shared
    @State private var screensOff = WindDownLog.isMarked()
    @State private var showBreathe = false
    @AppStorage("windDownSounds") private var soundsOn = true
    // Pre/post Pre-Sleep Arousal check-in bracketing the breathing intervention.
    @State private var psas = PSASStore.shared
    @State private var showPre = false
    @State private var showPost = false
    @State private var showResult = false
    @State private var trackedSessionID: UUID?
    @State private var pendingBreathe = false
    @State private var pendingPost = false
    @State private var pendingResult = false
    #if canImport(FamilyControls)
    @State private var shield = WindDownShieldService.shared
    @State private var showAppPicker = false
    #endif
    #if canImport(HomeKit)
    @State private var lighting = HomeLightingService.shared
    #endif

    private var active: Bool { noise.isPlaying || relax.isSpeaking }

    private var windDownTime: Date? {
        let plan = DayPlan.build(rhythm: AlertnessProvider.rhythm(health: health, now: Date()), now: Date())
        return plan.items.first { $0.kind == .windDown }?.time
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                startCard
                breatheCard
                checklist
                #if canImport(FamilyControls)
                shieldCard
                #endif
                #if canImport(HomeKit)
                lightingCard
                #endif
                screensOffCard
            }
            .padding()
        }
        .navigationTitle("Wind Down")
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $showAppPicker,
                              selection: Binding(get: { shield.selection }, set: { shield.selection = $0 }))
        .task { await shield.requestAuthorization() }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(.ocean)
            if let t = windDownTime {
                Text("Wind down around \(t.formatted(.dateTime.hour().minute()))")
                    .font(.headline)
            } else {
                Text("Wind down").font(.headline)
            }
            Text("Bring your alertness *down* to protect tonight's sleep — evening light and screens are what keep it up.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Start wind-down

    private var startCard: some View {
        VStack(spacing: 10) {
            Button {
                if active {
                    relax.stop(); noise.fadeOut()
                    #if canImport(FamilyControls)
                    shield.unshield()
                    #endif
                } else {
                    if soundsOn { noise.play() }
                    #if canImport(FamilyControls)
                    shield.shield()
                    #endif
                    #if canImport(HomeKit)
                    if lighting.syncEnabled { lighting.warm() }
                    #endif
                }
            } label: {
                Label(active ? "Stop wind-down" : "Start wind-down",
                      systemImage: active ? "stop.fill" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding()
                    .background(active ? AnyShapeStyle(.red.gradient) : AnyShapeStyle(.ocean.gradient),
                                in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            // Opt-in — wind-down doesn't force relaxing sounds on you.
            audioToggle("Relaxing sounds", on: "speaker.wave.2.fill", off: "speaker.slash.fill", isOn: $soundsOn)
                .onChange(of: soundsOn) { _, on in if active { on ? noise.play() : noise.fadeOut() } }
        }
    }

    private func audioToggle(_ title: String, on: String, off: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: isOn.wrappedValue ? on : off)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background((isOn.wrappedValue ? Color.ocean.opacity(0.18) : Color.secondary.opacity(0.12)),
                            in: Capsule())
                .foregroundStyle(isOn.wrappedValue ? .ocean : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Visual breathing guide

    private var breatheCard: some View {
        VStack(spacing: 10) {
            Button { showBreathe = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wind").font(.title3).foregroundStyle(.ocean)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Breathe with the circle").font(.subheadline.weight(.semibold))
                        Text("A visual, haptic-paced 4-7-8 — follow along, no counting.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)

            // Optional: rate how wound-up you are before and after, to see it working.
            Button { trackedSessionID = nil; showPre = true } label: {
                Label("Track before & after", systemImage: "chart.line.downtrend.xyaxis")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color.ocean.opacity(0.12), in: Capsule())
                    .foregroundStyle(.ocean)
            }
            .buttonStyle(.plain)
        }
        // The before check-in → breathing → after check-in → result, chained so only
        // one presentation is up at a time.
        .fullScreenCover(isPresented: $showBreathe, onDismiss: {
            if pendingPost { pendingPost = false; showPost = true }
        }) { BreathingGuideView() }
        .sheet(isPresented: $showPre, onDismiss: {
            if pendingBreathe { pendingBreathe = false; pendingPost = true; showBreathe = true }
        }) {
            PSASSurveyView(title: "Before", subtitle: "How wound-up are you right now — in your body and your mind?") { answers in
                trackedSessionID = psas.startSession(pre: answers)
                pendingBreathe = true
                showPre = false
            }
        }
        .sheet(isPresented: $showPost, onDismiss: {
            if pendingResult { pendingResult = false; showResult = true }
        }) {
            PSASSurveyView(title: "After", subtitle: "And now? Rate the same things after breathing.") { answers in
                if let id = trackedSessionID { psas.completeSession(id, post: answers) }
                pendingResult = true
                showPost = false
            }
        }
        .sheet(isPresented: $showResult) {
            if let id = trackedSessionID, let session = psas.session(id: id) {
                PSASResultView(session: session)
            }
        }
    }

    // MARK: - Checklist

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tonight").font(.headline)
            point("light.min", "Dim & warm your lights",
                  "And turn on Night Shift / a warm display. (Apps can't switch it for you — it's in Settings → Display.)")
            point("iphone.slash", "Screens off before bed",
                  "Aim to put screens down ~30–60 min before sleep — the light and the scrolling both keep you alert.")
            point("clock.badge.checkmark", "Consistent, earlier night",
                  "After a short night, an earlier bedtime is the real fix — it lifts tomorrow's whole curve.")
            point("snowflake", "Cool, dark, quiet room",
                  "A cooler, dark room helps your body temperature drop into sleep.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func point(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.ocean).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Block distracting apps (Wind-Down Mode)

    #if canImport(FamilyControls)
    private var isAllowlist: Bool { shield.mode == .allowlist }

    private var shieldCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "hand.raised.fill").foregroundStyle(.ocean)
                Text("Block distracting apps").font(.subheadline.weight(.semibold))
                Spacer()
                if shield.isShielding {
                    Text("Blocking").font(.caption.weight(.medium)).foregroundStyle(.ocean)
                }
            }
            Picker("Mode", selection: Binding(get: { shield.mode }, set: { shield.mode = $0 })) {
                Text("Block these").tag(WindDownShieldMode.blocklist)
                Text("Bare Necessities").tag(WindDownShieldMode.allowlist)
            }
            .pickerStyle(.segmented)
            Text(isAllowlist
                 ? "Bare Necessities blocks *everything* except the few apps you allow — pick **Phone, Messages, Clock, FaceTime, and SleepBank** so you stay reachable and can turn this off."
                 : "While wind-down runs, the apps you choose are blocked — so the scroll can't keep you up.")
                .font(.caption).foregroundStyle(.secondary)
            Button { showAppPicker = true } label: {
                Label(buttonLabel, systemImage: "app.badge.checkmark").font(.caption.weight(.medium))
            }
            if shield.hasSelection {
                Toggle(isOn: Binding(get: { shield.autoSchedule }, set: { shield.autoSchedule = $0 })) {
                    Text("Block automatically every evening").font(.caption)
                }
                .disabled(!shield.isAuthorized)
                Text("Shields on its own from wind-down to wake — even if the app's closed.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !shield.isAuthorized {
                Text("Needs Screen Time permission (auto-provisions on a development build) — see docs/WIND_DOWN_MODE.md.")
                    .font(.caption2).foregroundStyle(.sand)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var buttonLabel: String {
        switch (isAllowlist, shield.hasSelection) {
        case (true, true):   return "Edit allowed apps"
        case (true, false):  return "Choose apps to allow"
        case (false, true):  return "Edit blocked apps"
        case (false, false): return "Choose apps to block"
        }
    }
    #endif

    // MARK: - Home lighting (HomeKit color temperature)

    #if canImport(HomeKit)
    private var lightingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.led.fill").foregroundStyle(.sand)
                Text("Warm your lights at wind-down").font(.subheadline.weight(.semibold))
                Spacer()
                if lighting.lightCount > 0 {
                    Text("\(lighting.lightCount) light\(lighting.lightCount == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("When wind-down starts, shift your HomeKit lights warm (the hue, not the brightness) — the room cues your body that it's nearly sleep.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle(isOn: Binding(get: { lighting.syncEnabled }, set: { lighting.syncEnabled = $0 })) {
                Text("Warm lights at wind-down").font(.caption)
            }
            Button { lighting.warm() } label: {
                Label("Warm now", systemImage: "sun.haze.fill").font(.caption2)
            }.buttonStyle(.bordered).tint(.sand)
            Text("For an all-day daylight curve, use Apple Adaptive Lighting (or your Hue setup) — SleepBank just handles the wind-down moment.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    #endif

    // MARK: - Screens-off self-report

    private var screensOffCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $screensOff) {
                HStack {
                    Text("Screens off tonight").font(.subheadline.weight(.semibold))
                    if WindDownLog.streak > 0 { Text("🌙 \(WindDownLog.streak)").font(.subheadline) }
                }
            }
            .onChange(of: screensOff) { _, on in WindDownLog.mark(on) }
            Text("Your call — iPhone doesn't let apps read your Screen Time. Tap when you put the phone down for the night.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
