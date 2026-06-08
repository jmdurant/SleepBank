//
//  MuseService.swift
//  SleepBank
//
//  Harvested from SexKit. Connects to a Muse headband over CoreBluetooth and
//  streams raw 4-channel EEG (TP9/AF7/AF8/TP10) at 256 Hz, unpacking the 12-bit
//  packed samples and feeding them to EEGSleepProcessor. No InteraXon SDK — the
//  BLE protocol is spoken directly (based on the muse-js / XvMuse reversing).
//
//  Per the project's topology decision, Muse pairs to the *phone* (watchOS won't
//  do generic third-party BLE), so this lives on the iOS side and provides the
//  high-fidelity at-home nap mode plus the n=1 validation signal against the
//  watch-only onset detector.
//

import Foundation
import CoreBluetooth
import os

private let mlog = Logger(subsystem: "com.doctordurant.sleepbank", category: "Muse")

@Observable
class MuseService: NSObject {

    static let shared = MuseService()

    var isScanning = false
    var isConnected = false
    var isStreaming = false
    var deviceName: String?

    // Stream diagnostics (also logged).
    var subscribedChannels = 0
    var packetsReceived = 0
    var lastPacketLength = 0

    let eeg = EEGSleepProcessor()

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var eegForwardCounter = 0
    private var didStartStreaming = false

    // Muse BLE UUIDs
    private let museServiceUUID = CBUUID(string: "0000fe8d-0000-1000-8000-00805f9b34fb")
    private let controlCharUUID = CBUUID(string: "273e0001-4c4d-454d-96be-f03bac821358")
    private let eeg1CharUUID = CBUUID(string: "273e0003-4c4d-454d-96be-f03bac821358")  // TP9
    private let eeg2CharUUID = CBUUID(string: "273e0004-4c4d-454d-96be-f03bac821358")  // AF7
    private let eeg3CharUUID = CBUUID(string: "273e0005-4c4d-454d-96be-f03bac821358")  // AF8
    private let eeg4CharUUID = CBUUID(string: "273e0006-4c4d-454d-96be-f03bac821358")  // TP10

    func startScanning() {
        guard centralManager == nil else {
            if centralManager?.state == .poweredOn { beginScan() }
            return
        }
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func disconnect() {
        if let peripheral { centralManager?.cancelPeripheralConnection(peripheral) }
        isConnected = false
        isStreaming = false
    }

    private func beginScan() {
        isScanning = true
        centralManager?.scanForPeripherals(withServices: [museServiceUUID], options: nil)
    }

    private func startStreaming() {
        guard let controlCharacteristic, peripheral != nil else {
            mlog.error("startStreaming: no control characteristic")
            return
        }
        eeg.reset()
        let supportsResp = controlCharacteristic.properties.contains(.write)
        let supportsNoResp = controlCharacteristic.properties.contains(.writeWithoutResponse)
        mlog.info("startStreaming: control props resp=\(supportsResp) noResp=\(supportsNoResp)")
        // Muse control protocol: halt → set preset (p21 enables the 4 EEG channels)
        // → status → resume. Commands are length-prefixed and newline-terminated.
        let sequence = ["h", "p21", "s", "d"]
        for (i, cmd) in sequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) { [weak self] in
                self?.writeCommand(cmd)
            }
        }
        isStreaming = true
    }

    /// Encode and send a Muse control command: [length, ascii…, 0x0A].
    private func writeCommand(_ command: String) {
        guard let controlCharacteristic, let peripheral else { return }
        var bytes: [UInt8] = [UInt8(command.utf8.count + 1)]
        bytes.append(contentsOf: Array(command.utf8))
        bytes.append(0x0A)   // newline
        let type: CBCharacteristicWriteType =
            controlCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        mlog.info("write cmd '\(command, privacy: .public)' bytes=\(bytes, privacy: .public) type=\(type == .withResponse ? "resp" : "noResp", privacy: .public)")
        peripheral.writeValue(Data(bytes), for: controlCharacteristic, type: type)
    }

    /// Unpack a Muse EEG packet: 2-byte sequence header then 12 × 12-bit samples.
    private func parseEEGPacket(_ data: Data, channel: Int) {
        guard data.count >= 20, channel < 4 else {
            if packetsReceived <= 12 { mlog.notice("short/odd EEG packet len=\(data.count) ch=\(channel)") }
            return
        }
        let bytes = [UInt8](data)
        var samples: [Float] = []
        for i in 0..<12 {
            let byteIndex = 2 + (i * 3 / 2)
            if byteIndex + 1 >= bytes.count { break }
            let sample: UInt16
            if i % 2 == 0 {
                sample = (UInt16(bytes[byteIndex]) << 4) | (UInt16(bytes[byteIndex + 1]) >> 4)
            } else {
                sample = (UInt16(bytes[byteIndex] & 0x0F) << 8) | UInt16(bytes[byteIndex + 1])
            }
            samples.append(Float(sample))
        }
        eeg.feedSamples(channel: channel, samples: samples)

        // Channel 0 drives a processor update (~1/s). Forward the EEG onset signal
        // to the watch nap loop, but only with good contact and throttled.
        if channel == 0 {
            eegForwardCounter += 1
            if eegForwardCounter % 8 == 0, eeg.hasGoodSignal {
                PhoneConnectivity.shared.sendEEG(
                    onsetConfidence: Double(eeg.onsetIndex),
                    deepApproaching: eeg.deepSleepApproaching
                )
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension MuseService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { beginScan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard (peripheral.name ?? "").lowercased().contains("muse") else { return }
        self.peripheral = peripheral
        self.deviceName = peripheral.name
        central.stopScan()
        isScanning = false
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        didStartStreaming = false
        subscribedChannels = 0
        packetsReceived = 0
        peripheral.delegate = self
        mlog.info("connected to \(peripheral.name ?? "?", privacy: .public); discovering services")
        peripheral.discoverServices(nil)   // discover all, in case EEG lives elsewhere
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        mlog.error("failed to connect: \(error?.localizedDescription ?? "?", privacy: .public)")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        mlog.notice("disconnected: \(error?.localizedDescription ?? "clean", privacy: .public)")
        isConnected = false
        isStreaming = false
    }
}

// MARK: - CBPeripheralDelegate

extension MuseService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        mlog.info("discovered \(services.count) services: \(services.map { $0.uuid.uuidString }.joined(separator: ","), privacy: .public)")
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            mlog.info("char \(char.uuid.uuidString, privacy: .public) props=\(char.properties.rawValue)")
            switch char.uuid {
            case controlCharUUID:
                controlCharacteristic = char
            case eeg1CharUUID, eeg2CharUUID, eeg3CharUUID, eeg4CharUUID:
                peripheral.setNotifyValue(true, for: char)
                subscribedChannels += 1
            default:
                break
            }
        }
        // Start once we have the control char and have subscribed to EEG channels.
        if controlCharacteristic != nil, subscribedChannels >= 4, !didStartStreaming {
            didStartStreaming = true
            mlog.info("all chars ready (subscribed=\(self.subscribedChannels)); starting stream")
            startStreaming()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            mlog.error("control write FAILED: \(error.localizedDescription, privacy: .public)")
        } else {
            mlog.info("control write ok")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            mlog.error("notify enable failed for \(characteristic.uuid.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        packetsReceived += 1
        lastPacketLength = data.count
        if packetsReceived <= 8 {
            mlog.info("EEG packet \(self.packetsReceived) uuid=\(characteristic.uuid.uuidString, privacy: .public) len=\(data.count)")
        }
        switch characteristic.uuid {
        case eeg1CharUUID: parseEEGPacket(data, channel: 0)
        case eeg2CharUUID: parseEEGPacket(data, channel: 1)
        case eeg3CharUUID: parseEEGPacket(data, channel: 2)
        case eeg4CharUUID: parseEEGPacket(data, channel: 3)
        default: break
        }
    }
}
