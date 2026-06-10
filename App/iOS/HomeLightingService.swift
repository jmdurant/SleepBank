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

    /// Pick a sensible hue for the clock time (used on app open / wind-down stop).
    func syncToTimeOfDay(_ now: Date = Date()) {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 19...23, 0..<6: setWarm()
        case 6..<10:         setCool()
        default:             setNeutral()
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
