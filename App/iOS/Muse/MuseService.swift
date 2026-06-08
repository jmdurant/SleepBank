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

@Observable
class MuseService: NSObject {

    var isScanning = false
    var isConnected = false
    var isStreaming = false
    var deviceName: String?

    let eeg = EEGSleepProcessor()

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?

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
        guard let controlCharacteristic, let peripheral else { return }
        eeg.reset()
        if let data = "d".data(using: .utf8) {   // "d" = start data streaming
            peripheral.writeValue(data, for: controlCharacteristic, type: .withResponse)
            isStreaming = true
        }
    }

    /// Unpack a Muse EEG packet: 2-byte sequence header then 12 × 12-bit samples.
    private func parseEEGPacket(_ data: Data, channel: Int) {
        guard data.count >= 20, channel < 4 else { return }
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
        peripheral.delegate = self
        peripheral.discoverServices([museServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        isStreaming = false
    }
}

// MARK: - CBPeripheralDelegate

extension MuseService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        service.characteristics?.forEach { char in
            switch char.uuid {
            case controlCharUUID:
                controlCharacteristic = char
                startStreaming()
            case eeg1CharUUID, eeg2CharUUID, eeg3CharUUID, eeg4CharUUID:
                peripheral.setNotifyValue(true, for: char)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case eeg1CharUUID: parseEEGPacket(data, channel: 0)
        case eeg2CharUUID: parseEEGPacket(data, channel: 1)
        case eeg3CharUUID: parseEEGPacket(data, channel: 2)
        case eeg4CharUUID: parseEEGPacket(data, channel: 3)
        default: break
        }
    }
}
