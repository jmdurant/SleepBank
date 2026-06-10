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
    #if canImport(FamilyControls)
    @State private var shield = WindDownShieldService.shared
    @State private var showAppPicker = false
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
                checklist
                #if canImport(FamilyControls)
                shieldCard
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
            Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(.purple)
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
        Button {
            if active {
                relax.stop(); noise.fadeOut()
                #if canImport(FamilyControls)
                shield.unshield()
                #endif
            } else {
                noise.play()
                relax.start(relax.guide == .none ? .breathing478 : relax.guide)
                #if canImport(FamilyControls)
                shield.shield()
                #endif
            }
        } label: {
            Label(active ? "Stop wind-down" : "Start wind-down",
                  systemImage: active ? "stop.fill" : "play.fill")
                .font(.headline).frame(maxWidth: .infinity).padding()
                .background(active ? AnyShapeStyle(.red.gradient) : AnyShapeStyle(.purple.gradient),
                            in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Text(active ? "Relaxing sounds + paced breathing playing" : "Relaxing sounds + a paced-breathing guide")
                .font(.caption2).foregroundStyle(.secondary).offset(y: 18)
        }
        .padding(.bottom, 18)
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
            Image(systemName: icon).foregroundStyle(.purple).frame(width: 24)
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
                Image(systemName: "hand.raised.fill").foregroundStyle(.purple)
                Text("Block distracting apps").font(.subheadline.weight(.semibold))
                Spacer()
                if shield.isShielding {
                    Text("Blocking").font(.caption.weight(.medium)).foregroundStyle(.purple)
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
            if !shield.isAuthorized {
                Text("Needs Screen Time permission (auto-provisions on a development build) — see docs/WIND_DOWN_MODE.md.")
                    .font(.caption2).foregroundStyle(.orange)
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
