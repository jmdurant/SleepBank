//
//  HomeLightingService.swift
//  SleepBank
//
//  SleepBank as a circadian-lighting engine (for the ~everyone who doesn't run a
//  Homebridge daylight plugin): it computes the same location-aware solar
//  color-temperature curve (SleepBankCore.CircadianLighting) and applies it to all
//  HomeKit lights via a single **scene** (HMActionSet), plus a hard warm shift at
//  wind-down. Color temperature only (not brightness).
//
//  Honest limits: an iOS app can't recompute continuously in the background like a
//  Homebridge server — it applies the curve when the app is active and at sleep
//  events. Fully-unattended continuous control needs HomeKit timer automations on a
//  Home hub (next step). Needs the (ungated) HomeKit entitlement + a Home hub for
//  reliable whole-house control. Untestable without real bulbs + device.
//

import Foundation
import SwiftUI

#if canImport(HomeKit)
import HomeKit
import CoreLocation
import SleepBankCore

@Observable
final class HomeLightingService: NSObject, HMHomeManagerDelegate, CLLocationManagerDelegate {
    static let shared = HomeLightingService()

    private let manager = HMHomeManager()
    private let locationManager = CLLocationManager()
    private let sceneName = "SleepBank Lighting"

    private(set) var lightCount = 0
    @ObservationIgnored private var coordinate: CLLocationCoordinate2D?

    /// Warm/cool bounds in Kelvin (Hue ambiance ≈ 2200–6500 K).
    var warmK = 2700
    var coolK = 5000

    var syncEnabled: Bool = UserDefaults.standard.bool(forKey: "homeLightingSync") {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: "homeLightingSync") }
    }

    override init() {
        super.init()
        manager.delegate = self
        locationManager.delegate = self
    }

    var isAuthorized: Bool { manager.authorizationStatus.contains(.authorized) }
    var hasLocation: Bool { coordinate != nil }

    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }

    // MARK: - Target (the curve)

    /// Color temperature (Kelvin) for now: location-aware solar curve when we have
    /// coordinates, else anchored to the user's wake rhythm.
    func currentKelvin(_ now: Date = Date()) -> Int {
        if let c = coordinate {
            return CircadianLighting.kelvin(at: now, latitude: c.latitude, longitude: c.longitude,
                                            warmK: warmK, coolK: coolK)
        }
        if let snap = RhythmSnapshot.load() {
            return CircadianLighting.kelvinFromRhythm(at: now, wakeTime: snap.wakeTime, warmK: warmK, coolK: coolK)
        }
        return warmK
    }

    // MARK: - Apply (via one scene)

    func applyCircadian() { applyScene(mireds: CircadianLighting.kelvinToMireds(currentKelvin())) }
    func setWarm()        { applyScene(mireds: CircadianLighting.kelvinToMireds(warmK)) }
    func setCool()        { applyScene(mireds: CircadianLighting.kelvinToMireds(coolK)) }

    /// Set every light's color temperature at once via a reusable "SleepBank
    /// Lighting" scene — atomic, and visible/triggerable in the Home app.
    private func applyScene(mireds: Int) {
        guard let home = manager.homes.first else { return }
        let chars = colorTempCharacteristics()
        guard !chars.isEmpty else { return }
        if let set = home.actionSets.first(where: { $0.name == sceneName }) {
            rebuild(set, mireds: mireds, chars: chars, home: home)
        } else {
            home.addActionSet(withName: sceneName) { [weak self] set, _ in
                guard let self, let set else { return }
                self.rebuild(set, mireds: mireds, chars: chars, home: home)
            }
        }
    }

    private func rebuild(_ set: HMActionSet, mireds: Int, chars: [HMCharacteristic], home: HMHome) {
        let removal = DispatchGroup()
        for action in set.actions { removal.enter(); set.removeAction(action) { _ in removal.leave() } }
        removal.notify(queue: .main) {
            let additions = DispatchGroup()
            for ch in chars {
                let value = self.clamp(mireds, ch)
                additions.enter()
                set.addAction(HMCharacteristicWriteAction(characteristic: ch, targetValue: NSNumber(value: value))) { _ in
                    additions.leave()
                }
            }
            additions.notify(queue: .main) { home.executeActionSet(set) { _ in } }
        }
    }

    // MARK: - HomeKit / Location plumbing

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        lightCount = colorTempCharacteristics().count
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func colorTempCharacteristics() -> [HMCharacteristic] {
        guard let home = manager.homes.first else { return [] }
        return home.accessories
            .flatMap(\.services)
            .filter { $0.serviceType == HMServiceTypeLightbulb }
            .flatMap(\.characteristics)
            .filter { $0.characteristicType == HMCharacteristicTypeColorTemperature }
    }

    private func clamp(_ mireds: Int, _ ch: HMCharacteristic) -> Int {
        let lo = ch.metadata?.minimumValue?.intValue ?? 140
        let hi = ch.metadata?.maximumValue?.intValue ?? 500
        return min(max(mireds, lo), hi)
    }
}
#endif
