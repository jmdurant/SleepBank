// Muse BLE EEG stream for SleepBank (phone-side connection).
import Foundation
import CoreBluetooth
import os

private let mlog = Logger(subsystem: "com.doctordurant.sleepbank", category: "Muse")

@Observable
class MuseService: NSObject {

    static let shared = MuseService()

    var isScanning = false
    var isConnecting = false
    var isBusy: Bool { isScanning || isConnecting || isConnected }
    var lastError: String?
    private var channelDates: [Date?] = Array(repeating: nil, count: 4)
    private var sequenceNumbers: [UInt16?] = Array(repeating: nil, count: 4)
    var hasFreshEEG: Bool {
        isStreaming && eeg.hasGoodSignal
        && SensorFreshness.isFresh(eeg.lastFrameDate, within: SensorFreshness.eeg)
        && [1, 2].allSatisfy {
            SensorFreshness.isFresh(channelDates[$0], within: SensorFreshness.eeg)
        }
    }
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
    private var didStartStreaming = false
    private var wantsConnection = false
    private var notifiedChannels: Set<CBUUID> = []
    private var streamGeneration = UUID()

    // Muse BLE UUIDs
    private let museServiceUUID = CBUUID(string: "0000fe8d-0000-1000-8000-00805f9b34fb")
    private let controlCharUUID = CBUUID(string: "273e0001-4c4d-454d-96be-f03bac821358")
    private let eeg1CharUUID = CBUUID(string: "273e0003-4c4d-454d-96be-f03bac821358")  // TP9
    private let eeg2CharUUID = CBUUID(string: "273e0004-4c4d-454d-96be-f03bac821358")  // AF7
    private let eeg3CharUUID = CBUUID(string: "273e0005-4c4d-454d-96be-f03bac821358")  // AF8
    private let eeg4CharUUID = CBUUID(string: "273e0006-4c4d-454d-96be-f03bac821358")  // TP10

    func startScanning() {
        guard !isConnected, !isConnecting else { return }
        wantsConnection = true
        isScanning = true
        lastError = nil
        guard centralManager == nil else {
            if centralManager?.state == .poweredOn { beginScan() }
            return
        }
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func disconnect() {
        wantsConnection = false
        centralManager?.stopScan()
        if let peripheral { centralManager?.cancelPeripheralConnection(peripheral) }
        self.peripheral = nil
        resetConnection()
    }

    private func resetConnection() {
        isScanning = false
        isConnecting = false
        isConnected = false
        isStreaming = false
        didStartStreaming = false
        controlCharacteristic = nil
        notifiedChannels.removeAll()
        subscribedChannels = 0
        streamGeneration = UUID()
        channelDates = Array(repeating: nil, count: 4)
        sequenceNumbers = Array(repeating: nil, count: 4)
        eeg.reset()
    }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        disconnect()
    }

    private func startIfReady() {
        guard isConnected, controlCharacteristic != nil, notifiedChannels.count == 4, !didStartStreaming else { return }
        didStartStreaming = true
        startStreaming()
    }

    private func beginScan() {
        guard wantsConnection, !isConnected, !isConnecting else { return }
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
        let generation = streamGeneration
        for (i, cmd) in sequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) { [weak self] in
                guard let self, self.isConnected, self.streamGeneration == generation else { return }
                self.writeCommand(cmd)
            }
        }
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
    func parseEEGPacket(_ data: Data, channel: Int, at now: Date = Date()) {
        guard isConnected else { return }
        guard data.count >= 20, (0..<4).contains(channel) else {
            if packetsReceived <= 12 { mlog.notice("short/odd EEG packet len=\(data.count) ch=\(channel)") }
            return
        }
        let bytes = [UInt8](data)
        let sequence = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        if (sequenceNumbers[channel].map { sequence != $0 &+ 1 } ?? false)
            || (channelDates[channel].map { now.timeIntervalSince($0) > 3 } ?? false) {
            // Do not concatenate gaps into a continuous FFT window or retain old contact quality.
            eeg.reset()
            channelDates = Array(repeating: nil, count: 4)
        }
        sequenceNumbers[channel] = sequence
        channelDates[channel] = now
        isStreaming = true
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
        let frameCount = eeg.processedFrameCount
        eeg.feedSamples(channel: channel, samples: samples)
        RawEEGRecorder.shared.record(channel: channel, samples: samples)
        if eeg.processedFrameCount != frameCount, hasFreshEEG {
            PhoneConnectivity.shared.sendEEG(
                onsetConfidence: Double(eeg.onsetIndex), deepApproaching: eeg.deepSleepApproaching
            )
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension MuseService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            beginScan()
        } else if central.state != .unknown && central.state != .resetting {
            resetConnection()
            isScanning = wantsConnection && central.state == .poweredOff
            lastError = "Bluetooth is unavailable."
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard wantsConnection, isScanning, (peripheral.name ?? "").lowercased().contains("muse") else { return }
        self.peripheral = peripheral
        self.deviceName = peripheral.name
        central.stopScan()
        isScanning = false
        isConnecting = true
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard wantsConnection, peripheral === self.peripheral else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        isConnecting = false
        isConnected = true
        lastError = nil
        didStartStreaming = false
        subscribedChannels = 0
        packetsReceived = 0
        peripheral.delegate = self
        mlog.info("connected to \(peripheral.name ?? "?", privacy: .public); discovering services")
        peripheral.discoverServices(nil)   // discover all, in case EEG lives elsewhere
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        lastError = error?.localizedDescription ?? "Could not connect to Muse."
        disconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        lastError = error?.localizedDescription
        self.peripheral = nil
        resetConnection()
    }
}

// MARK: - CBPeripheralDelegate

extension MuseService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral, isConnected else { return }
        if let error { fail(error); return }
        let services = peripheral.services ?? []
        mlog.info("discovered \(services.count) services: \(services.map { $0.uuid.uuidString }.joined(separator: ","), privacy: .public)")
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral, isConnected else { return }
        if let error { fail(error); return }
        for char in service.characteristics ?? [] {
            mlog.info("char \(char.uuid.uuidString, privacy: .public) props=\(char.properties.rawValue)")
            switch char.uuid {
            case controlCharUUID:
                controlCharacteristic = char
            case eeg1CharUUID, eeg2CharUUID, eeg3CharUUID, eeg4CharUUID:
                peripheral.setNotifyValue(true, for: char)

            default:
                break
            }
        }
        startIfReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, isConnected else { return }
        if let error {
            fail(error)
        } else {
            mlog.info("control write ok")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, isConnected else { return }
        if let error { fail(error); return }
        guard [eeg1CharUUID, eeg2CharUUID, eeg3CharUUID, eeg4CharUUID].contains(characteristic.uuid) else { return }
        if characteristic.isNotifying { notifiedChannels.insert(characteristic.uuid) }
        else {
            notifiedChannels.remove(characteristic.uuid)
            isStreaming = false
            eeg.reset()
        }
        subscribedChannels = notifiedChannels.count
        startIfReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, isConnected, didStartStreaming else { return }
        if let error { fail(error); return }
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
