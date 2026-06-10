//
//  HomeLightingService.swift
//  SleepBank
//
//  Drives the *hue* (color temperature) of HomeKit lights on the user's own rhythm
//  — warm at wind-down, cool in the morning. Apple's Adaptive Lighting handles the
//  smooth all-day curve on a generic sun schedule; our value-add is shifting the key
//  transitions to *your* actual wind-down / wake times. We set color temperature
//  only (not brightness).
//
//  Needs the (ungated) `com.apple.developer.homekit` entitlement + an
//  NSHomeKitUsageDescription. Untestable without real bulbs + device.
//

import Foundation

#if canImport(HomeKit)
import HomeKit

@Observable
final class HomeLightingService: NSObject, HMHomeManagerDelegate {
    static let shared = HomeLightingService()

    private let manager = HMHomeManager()
    /// Number of color-temperature-capable lights found (for the UI).
    private(set) var lightCount = 0

    /// Mireds: lower = cooler/bluer, higher = warmer/amber.
    static let warmMireds = 450      // evening / wind-down
    static let neutralMireds = 320   // daytime
    static let coolMireds = 250      // morning

    var syncEnabled: Bool = UserDefaults.standard.bool(forKey: "homeLightingSync") {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: "homeLightingSync") }
    }

    override init() {
        super.init()
        manager.delegate = self
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        lightCount = colorTempCharacteristics().count
    }

    var isAuthorized: Bool {
        manager.authorizationStatus.contains(.authorized)
    }

    // MARK: - Transitions

    func setWarm()    { write(mireds: Self.warmMireds) }
    func setCool()    { write(mireds: Self.coolMireds) }
    func setNeutral() { write(mireds: Self.neutralMireds) }

    /// Pick a hue anchored to the user's *own* rhythm (wake → wind-down), not fixed
    /// clock hours — so it tracks their schedule regardless of location/season.
    /// Apple Adaptive Lighting already does the location-aware solar curve; this is
    /// the personal-transitions layer. Falls back to 7:00–22:30 without sleep data.
    func syncToTimeOfDay(_ now: Date = Date()) {
        let cal = Calendar.current
        func minutesOfDay(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }

        let wakeMin: Int
        let awakeLength: Int   // minutes from wake to wind-down (the "day")
        if let snap = RhythmSnapshot.load() {
            wakeMin = minutesOfDay(snap.wakeTime)
            awakeLength = Int(15.5 * 60)   // wind-down ≈ wake + 15.5 h
        } else {
            wakeMin = 7 * 60
            awakeLength = Int(15.5 * 60)
        }

        // Minutes since wake, circular over 24 h — handles wind-down past midnight.
        let sinceWake = (((minutesOfDay(now) - wakeMin) % 1440) + 1440) % 1440
        if sinceWake >= awakeLength {
            setWarm()         // past wind-down → evening / overnight
        } else if sinceWake < 180 {
            setCool()         // first ~3 h after waking
        } else {
            setNeutral()      // the day
        }
    }

    // MARK: - HomeKit plumbing

    private func colorTempCharacteristics() -> [HMCharacteristic] {
        guard let home = manager.homes.first else { return [] }
        return home.accessories
            .flatMap(\.services)
            .filter { $0.serviceType == HMServiceTypeLightbulb }
            .flatMap(\.characteristics)
            .filter { $0.characteristicType == HMCharacteristicTypeColorTemperature }
    }

    private func write(mireds: Int) {
        guard syncEnabled || true else { return }   // callers gate on syncEnabled
        for ch in colorTempCharacteristics() {
            let lo = ch.metadata?.minimumValue?.intValue ?? 140
            let hi = ch.metadata?.maximumValue?.intValue ?? 500
            ch.writeValue(min(max(mireds, lo), hi)) { _ in }
        }
    }
}
#endif
