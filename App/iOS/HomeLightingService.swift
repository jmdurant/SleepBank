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
    /// Run the curve unattended via HomeKit timer automations (needs a Home hub).
    var autoRunEnabled: Bool = UserDefaults.standard.bool(forKey: "homeLightingAutoRun") {
        didSet {
            UserDefaults.standard.set(autoRunEnabled, forKey: "homeLightingAutoRun")
            Task { autoRunEnabled ? await installAutomations() : await removeAutomations() }
        }
    }

    /// Clock hours the curve is stepped into for the daily automations.
    private let stepHours = [0, 5, 7, 9, 12, 15, 18, 21]
    private let autoPrefix = "SleepBank Auto"

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

    // MARK: - Unattended automations (run on a Home hub, app closed)

    /// Materialize the day's curve as one stepped scene + daily timer trigger per
    /// step. The Home hub fires them through the day even with the app closed. Call
    /// to (re)install — e.g. daily — so values track the season. Idempotent: clears
    /// the previous SleepBank automations first.
    func installAutomations() async {
        guard let home = manager.homes.first else { return }
        await removeAutomations()
        let chars = colorTempCharacteristics()
        guard !chars.isEmpty else { return }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())

        for hour in stepHours {
            guard let stepTime = cal.date(byAdding: .hour, value: hour, to: startOfDay) else { continue }
            let mireds = CircadianLighting.kelvinToMireds(currentKelvin(stepTime))
            guard let scene = await addActionSet(home, name: "\(autoPrefix) \(hour)") else { continue }
            for ch in chars { await addAction(scene, ch, clamp(mireds, ch)) }

            let fire = nextOccurrence(hour: hour, calendar: cal)
            let trigger = HMTimerTrigger(name: "\(autoPrefix) \(hour)", fireDate: fire,
                                         timeZone: nil, recurrence: DateComponents(day: 1),
                                         recurrenceCalendar: cal)
            await add(trigger, to: home)
            await addActionSet(scene, to: trigger)
            await enable(trigger)
        }
    }

    func removeAutomations() async {
        guard let home = manager.homes.first else { return }
        for trigger in home.triggers where trigger.name.hasPrefix(autoPrefix) {
            await remove(trigger, from: home)
        }
        for set in home.actionSets where set.name.hasPrefix(autoPrefix) {
            await remove(set, from: home)
        }
    }

    private func nextOccurrence(hour: Int, calendar: Calendar) -> Date {
        let now = Date()
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour; comps.minute = 0
        let today = calendar.date(from: comps) ?? now
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    // Async wrappers over HomeKit's completion-handler APIs (readability).
    private func addActionSet(_ home: HMHome, name: String) async -> HMActionSet? {
        await withCheckedContinuation { c in home.addActionSet(withName: name) { set, _ in c.resume(returning: set) } }
    }
    private func addAction(_ set: HMActionSet, _ ch: HMCharacteristic, _ mireds: Int) async {
        await withCheckedContinuation { c in
            set.addAction(HMCharacteristicWriteAction(characteristic: ch, targetValue: NSNumber(value: mireds))) { _ in c.resume() }
        }
    }
    private func add(_ trigger: HMTrigger, to home: HMHome) async {
        await withCheckedContinuation { c in home.addTrigger(trigger) { _ in c.resume() } }
    }
    private func addActionSet(_ set: HMActionSet, to trigger: HMTrigger) async {
        await withCheckedContinuation { c in trigger.addActionSet(set) { _ in c.resume() } }
    }
    private func enable(_ trigger: HMTrigger) async {
        await withCheckedContinuation { c in trigger.enable(true) { _ in c.resume() } }
    }
    private func remove(_ trigger: HMTrigger, from home: HMHome) async {
        await withCheckedContinuation { c in home.removeTrigger(trigger) { _ in c.resume() } }
    }
    private func remove(_ set: HMActionSet, from home: HMHome) async {
        await withCheckedContinuation { c in home.removeActionSet(set) { _ in c.resume() } }
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
