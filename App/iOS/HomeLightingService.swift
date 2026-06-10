//
//  HomeLightingService.swift
//  SleepBank
//
//  Trimmed to the one differentiated, defensible moment: warm your HomeKit lights
//  when wind-down starts (color temperature, not brightness) so the room cues
//  sleep. The all-day daylight curve is left to Apple Adaptive Lighting / the user's
//  existing setup — reimplementing it added little over a built-in commodity and was
//  the most fragile code in the app. Sets all lights at once via one Home scene.
//
//  Needs the (ungated) HomeKit entitlement + a Home hub for reliable whole-house
//  control. Untestable without real bulbs + device.
//

import Foundation
import SwiftUI

#if canImport(HomeKit)
import HomeKit

@Observable
final class HomeLightingService: NSObject, HMHomeManagerDelegate {
    static let shared = HomeLightingService()

    private let manager = HMHomeManager()
    private let sceneName = "SleepBank Wind Down"
    private let warmMireds = 370   // ≈ 2700 K

    private(set) var lightCount = 0

    var syncEnabled: Bool = UserDefaults.standard.bool(forKey: "homeLightingSync") {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: "homeLightingSync") }
    }

    override init() {
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool { manager.authorizationStatus.contains(.authorized) }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        lightCount = colorTempCharacteristics().count
    }

    /// Warm all lights — the wind-down moment — via one reusable Home scene.
    func warm() {
        guard let home = manager.homes.first else { return }
        let chars = colorTempCharacteristics()
        guard !chars.isEmpty else { return }
        if let set = home.actionSets.first(where: { $0.name == sceneName }) {
            rebuild(set, chars: chars, home: home)
        } else {
            home.addActionSet(withName: sceneName) { [weak self] set, _ in
                guard let self, let set else { return }
                self.rebuild(set, chars: chars, home: home)
            }
        }
    }

    private func rebuild(_ set: HMActionSet, chars: [HMCharacteristic], home: HMHome) {
        let removal = DispatchGroup()
        for action in set.actions { removal.enter(); set.removeAction(action) { _ in removal.leave() } }
        removal.notify(queue: .main) {
            let additions = DispatchGroup()
            for ch in chars {
                let value = self.clamp(self.warmMireds, ch)
                additions.enter()
                set.addAction(HMCharacteristicWriteAction(characteristic: ch, targetValue: NSNumber(value: value))) { _ in
                    additions.leave()
                }
            }
            additions.notify(queue: .main) { home.executeActionSet(set) { _ in } }
        }
    }

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
