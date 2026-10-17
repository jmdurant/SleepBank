//
//  PolarH10Service.swift
//  SleepBank
//
//  Polar H10 via the official (locally patched) Polar BLE SDK — the *full* SDK,
//  not the generic 0x180D heart-rate service. That's deliberate: only the SDK's
//  online streaming gives reliable continuous HR plus beat-to-beat RR intervals,
//  which is what we need for HR-drop onset detection and real HRV. Harvested from
//  SexKit and trimmed to its own published state (HR, RR/HRV, battery).
//

import Foundation
import PolarBleSdk
import RxSwift
import CoreBluetooth
import os.log

private let logger = Logger(subsystem: "com.doctordurant.sleepbank", category: "PolarH10")

@Observable
class PolarH10Service: NSObject {

    static let shared = PolarH10Service()

    // Connection / status
    var isConnected = false
    var isStreaming = false
    var deviceId: String?
    var deviceName: String?
    var batteryLevel: Int = -1
    var firmwareVersion: String?
    var lastStreamError: String?
    var streamingFeatureReady = false

    // Live signals
    var currentHeartRate: Int = 0
    var lastRRInterval: Double = 0          // ms
    var rrIntervals: [Double] = []          // rolling, ms
    var hrvRMSSD: Double = 0                 // ms
    var heartRateHistory: [HeartRateSample] = []   // rolling, for charting

    // Chest accelerometer — a real immobility source for phone naps.
    var isAccStreaming = false
    var movementIntensity: Double = 0        // 0…1, from chest accel
    var stillSeconds: TimeInterval = 0       // continuous seconds below the stillness threshold
    var isLyingDown = false                  // gravity aligned with the body's long axis
    var breathingRate: Double = 0            // breaths/min (estimate from chest accel)
    var accelX: Double = 0                   // live gravity vector (g), for orientation check
    var accelY: Double = 0
    var accelZ: Double = 0

    @ObservationIgnored private let now: () -> Date
    private var lastHRUpdate: Date?
    private var lastRRUpdate: Date?

    private func fresh(_ date: Date?, maxAge: TimeInterval = 10) -> Bool {
        guard isConnected, let date else { return false }
        return (0...maxAge).contains(now().timeIntervalSince(date))
    }
    var freshHeartRate: Int? { isStreaming && fresh(lastHRUpdate) && currentHeartRate > 0 ? currentHeartRate : nil }
    var freshHRV: Double? { isStreaming && fresh(lastRRUpdate) && hrvRMSSD > 0 ? hrvRMSSD : nil }
    var hasFreshMotion: Bool { isAccStreaming && fresh(lastAccUpdate, maxAge: 5) }
    var freshBreathingRate: Double? {
        hasFreshMotion && fresh(lastBreathPeak, maxAge: 12) && breathingRate > 0 ? breathingRate : nil
    }

    private func clearHeartRate() {
        isStreaming = false
        lastHRUpdate = nil; lastRRUpdate = nil
        currentHeartRate = 0; lastRRInterval = 0; hrvRMSSD = 0
        rrIntervals.removeAll()
    }

    private func clearMotion() {
        isAccStreaming = false
        lastAccUpdate = nil; lastBreathPeak = nil
        movementIntensity = 0; stillSeconds = 0; breathingRate = 0
        isLyingDown = false
        accBuffer.removeAll(); breathIntervals.removeAll()
        slowZ = 0; fastZ = 0; prevBreath = 0; prevPrevBreath = 0
    }

    private func clearSignals() {
        clearHeartRate()
        clearMotion()
        streamingFeatureReady = false
    }

    var posture: String { isLyingDown ? "Lying down" : "Upright" }

    private var api: PolarBleApi!
    private var hrDisposable: Disposable?
    private var accDisposable: Disposable?
    private var searchDisposable: Disposable?
    private var pendingAutoConnect = false
    @ObservationIgnored private var accBuffer: [Double] = []
    @ObservationIgnored private var lastAccUpdate: Date?
    // Breathing estimator state (slow chest-normal oscillation).
    @ObservationIgnored private var slowZ = 0.0
    @ObservationIgnored private var fastZ = 0.0
    @ObservationIgnored private var prevBreath = 0.0
    @ObservationIgnored private var prevPrevBreath = 0.0
    @ObservationIgnored private var lastBreathPeak: Date?
    @ObservationIgnored private var breathIntervals: [Double] = []

    override convenience init() { self.init(now: Date.init) }

    init(now: @escaping () -> Date) {
        self.now = now
        super.init()
        api = PolarBleApiDefaultImpl.polarImplementation(
            DispatchQueue.main,
            features: [
                .feature_hr,
                .feature_polar_online_streaming,
                .feature_battery_info,
                .feature_device_info,
            ]
        )
        api.observer = self
        api.deviceInfoObserver = self
        api.powerStateObserver = self
        api.deviceFeaturesObserver = self
    }

    // MARK: - Connect

    func autoConnect() {
        guard !isConnected else { return }
        pendingAutoConnect = true
        searchDisposable?.dispose()
        searchDisposable = api.searchForDevice()
            .observe(on: MainScheduler.instance)
            .subscribe(
                onNext: { [weak self] device in
                    guard let self, !self.isConnected, device.name.contains("H10") else { return }
                    self.searchDisposable?.dispose()
                    self.connect(deviceId: device.deviceId)
                },
                onError: { logger.notice("[PolarH10] Search error: \($0)") }
            )
        pendingAutoConnect = false
    }

    func connect(deviceId: String) {
        do {
            try api.connectToDevice(deviceId)
            self.deviceId = deviceId
        } catch {
            logger.notice("[PolarH10] Connect error: \(error)")
        }
    }

    func disconnect() {
        hrDisposable?.dispose(); hrDisposable = nil
        accDisposable?.dispose(); accDisposable = nil
        searchDisposable?.dispose(); searchDisposable = nil
        if let id = deviceId { try? api.disconnectFromDevice(id) }
        isConnected = false
        clearSignals()
        deviceId = nil
    }

    // MARK: - HR stream (HR + RR → HRV)

    private func startHRStream(_ id: String) {
        hrDisposable = api.startHrStreaming(id)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onNext: { [weak self] hrData in
                    guard let self, self.isConnected else { return }
                    for sample in hrData {
                        self.receiveHeartRate(bpm: Int(sample.hr), rr: sample.rrsMs.map(Double.init))
                    }
                    // Forward to the watch nap loop (best-effort when reachable).
                    if hrData.contains(where: { $0.hr > 0 }), let bpm = self.freshHeartRate {
                        PhoneConnectivity.shared.sendLiveHR(bpm: bpm, hrv: self.freshHRV ?? 0)
                    }
                },
                onError: { [weak self] in
                    self?.clearHeartRate()
                    self?.hrDisposable = nil
                    self?.lastStreamError = "HR: \($0)"
                    logger.notice("[PolarH10] HR stream error: \($0)")
                }
            )
    }

    /// One delivered HR packet. Freshness follows acquisition, not nap-loop polling.
    func receiveHeartRate(bpm: Int, rr: [Double]) {
        guard isConnected, bpm > 0 else { return }
        if !fresh(lastRRUpdate) { rrIntervals.removeAll(); hrvRMSSD = 0 }
        let date = now()
        currentHeartRate = bpm; lastHRUpdate = date; isStreaming = true
        heartRateHistory.append(HeartRateSample(timestamp: date, bpm: bpm))
        if heartRateHistory.count > 300 { heartRateHistory.removeFirst() }
        for value in rr where value > 0 {
            lastRRUpdate = date; lastRRInterval = value
            rrIntervals.append(value)
            if rrIntervals.count > 60 { rrIntervals.removeFirst() }
        }
        if rrIntervals.count >= 10 { computeHRV() }
    }

    // MARK: - Accelerometer stream (immobility + posture)

    private func startAccStream(_ id: String) {
        accDisposable = api.requestStreamSettings(id, feature: .acc)
            .asObservable()
            .flatMap { settings -> Observable<PolarAccData> in
                self.api.startAccStreaming(id, settings: settings.maxSettings())
            }
            .observe(on: MainScheduler.instance)
            .subscribe(
                onNext: { [weak self] accData in
                    guard let self, self.isConnected else { return }
                    for sample in accData {
                        self.feedAccel(x: Double(sample.x) / 1000.0,
                                       y: Double(sample.y) / 1000.0,
                                       z: Double(sample.z) / 1000.0)
                    }
                    self.isAccStreaming = true
                },
                onError: { [weak self] in
                    self?.clearMotion()
                    self?.accDisposable = nil
                    self?.lastStreamError = "ACC: \($0)"
                    logger.notice("[PolarH10] ACC stream error: \($0)")
                }
            )
    }

    /// Convert a chest-accel sample (g) into a normalized movement level + a
    /// running stillness duration, mirroring the watch's MotionService.
    func feedAccel(x: Double, y: Double, z: Double) {
        if !fresh(lastAccUpdate, maxAge: 5) { clearMotion() }
        accelX = x; accelY = y; accelZ = z
        let magnitude = (x * x + y * y + z * z).squareRoot()
        let movement = abs(magnitude - 1.0)        // subtract gravity

        accBuffer.append(movement)
        if accBuffer.count > 50 { accBuffer.removeFirst() }
        let avg = accBuffer.reduce(0, +) / Double(accBuffer.count)
        movementIntensity = min(avg / 0.5, 1.0)

        // Upright, the H10's X axis aligns with gravity (|x|≈1); lying down, gravity
        // shifts off X onto the chest-normal axis. (Calibrated to the strap's
        // typical mounting — empirically upright reads x≈-0.9.)
        isLyingDown = abs(x) < 0.5

        let now = self.now()
        let dt = lastAccUpdate.map { now.timeIntervalSince($0) } ?? 0
        lastAccUpdate = now
        if avg > 0.05 { stillSeconds = 0 } else { stillSeconds += dt }

        estimateBreathing(z: z, now: now, dt: dt)
    }

    /// Breathing rate from the slow chest-normal (z) oscillation: band-limit with
    /// a fast/slow EMA pair, peak-detect, and convert peak intervals to bpm.
    /// An estimate — respiration slows and regularizes at sleep onset.
    private func estimateBreathing(z: Double, now: Date, dt: TimeInterval) {
        guard dt > 0 else { return }
        slowZ += (z - slowZ) * min(1, dt / 8.0)     // ~posture / DC
        fastZ += (z - fastZ) * min(1, dt / 0.5)     // light smoothing
        let breath = fastZ - slowZ                  // ~breathing band

        if prevBreath > prevPrevBreath, prevBreath > breath, prevBreath > 0.008 {
            if let last = lastBreathPeak {
                let interval = now.timeIntervalSince(last)
                if interval > 2.0, interval < 10.0 {     // 6–30 breaths/min
                    breathIntervals.append(interval)
                    if breathIntervals.count > 8 { breathIntervals.removeFirst() }
                    let mean = breathIntervals.reduce(0, +) / Double(breathIntervals.count)
                    breathingRate = 60.0 / mean
                }
            }
            lastBreathPeak = now
        }
        prevPrevBreath = prevBreath
        prevBreath = breath
    }

    private func computeHRV() {
        guard rrIntervals.count >= 2 else { return }
        let diffs = zip(rrIntervals.dropFirst(), rrIntervals).map { $0 - $1 }
        let meanSquare = diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count)
        hrvRMSSD = meanSquare.squareRoot()
    }
}

// MARK: - PolarBleApiObserver

extension PolarH10Service: PolarBleApiObserver {
    func deviceConnecting(_ identifier: PolarDeviceInfo) {}

    func deviceConnected(_ identifier: PolarDeviceInfo) {
        clearSignals()
        isConnected = true
        deviceId = identifier.deviceId
        deviceName = identifier.name
        // Fallback: if the feature-ready callback never fires, try HR anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.isConnected, self.hrDisposable == nil, let id = self.deviceId else { return }
            self.startHRStream(id)
        }
    }

    func deviceDisconnected(_ identifier: PolarDeviceInfo, pairingError: Bool) {
        isConnected = false
        hrDisposable?.dispose(); hrDisposable = nil
        accDisposable?.dispose(); accDisposable = nil
        clearSignals()
    }
}

// MARK: - PolarBleApiDeviceInfoObserver

extension PolarH10Service: PolarBleApiDeviceInfoObserver {
    func batteryLevelReceived(_ identifier: String, batteryLevel: UInt) {
        self.batteryLevel = Int(batteryLevel)
    }
    func batteryChargingStatusReceived(_ identifier: String, chargingStatus: BleBasClient.ChargeState) {}
    func disInformationReceived(_ identifier: String, uuid: CBUUID, value: String) {
        if uuid.uuidString == "2A26" { firmwareVersion = value }
    }
    func disInformationReceivedWithKeysAsStrings(_ identifier: String, key: String, value: String) {}
}

// MARK: - PolarBleApiPowerStateObserver

extension PolarH10Service: PolarBleApiPowerStateObserver {
    func blePowerOn() {
        if pendingAutoConnect && !isConnected { autoConnect() }
    }
    func blePowerOff() {
        isConnected = false
        hrDisposable?.dispose(); hrDisposable = nil
        accDisposable?.dispose(); accDisposable = nil
        clearSignals()
    }
}

// MARK: - PolarBleApiDeviceFeaturesObserver

extension PolarH10Service: PolarBleApiDeviceFeaturesObserver {
    func bleSdkFeatureReady(_ identifier: String, feature: PolarBleSdkFeature) {
        if feature == .feature_polar_online_streaming {
            streamingFeatureReady = true
            if let id = deviceId, hrDisposable == nil { startHRStream(id) }
            // ACC needs PMD notifications enabled — brief delay after subscribe.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, let id = self.deviceId, self.isConnected, self.accDisposable == nil else { return }
                self.startAccStream(id)
            }
        }
    }
}
