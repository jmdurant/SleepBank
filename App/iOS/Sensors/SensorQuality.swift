import Foundation

/// Display expiry windows, based on each stream's cadence. These are not clinical thresholds.
enum SensorFreshness {
    static let heartRate: TimeInterval = 30
    static let temperature: TimeInterval = 180
    static let motion: TimeInterval = 5
    static let eeg: TimeInterval = 5
    static let relay: TimeInterval = 30

    static func isFresh(_ date: Date?, within age: TimeInterval, now: Date = Date()) -> Bool {
        guard let date else { return false }
        let elapsed = now.timeIntervalSince(date)
        return elapsed.isFinite && elapsed >= 0 && elapsed <= age
    }
}

/// Session-local temperature statistics. Invalid readings break baseline acquisition.
struct TemperatureSeries {
    private(set) var values: [Float] = []
    private(set) var baseline: Float?
    private(set) var peak: Float = 0
    private var stableValues: [Float] = []

    mutating func append(_ celsius: Float, confidence: Float, valid: Bool) {
        guard valid, celsius.isFinite, confidence.isFinite else {
            stableValues.removeAll()
            return
        }
        values.append(celsius)
        if values.count > 30 { values.removeFirst() }
        peak = max(peak, celsius)
        if baseline == nil {
            if confidence > 80 {
                stableValues.append(celsius)
                if stableValues.count == 3 { baseline = stableValues.reduce(0, +) / 3 }
            } else {
                stableValues.removeAll()
            }
        }
    }

    var delta: Float { guard let baseline, let last = values.last else { return 0 }; return last - baseline }
    var trend: String {
        guard values.count >= 4 else { return "stable" }
        let recent = values.suffix(2).reduce(0, +) / 2
        let previous = values.suffix(4).prefix(2).reduce(0, +) / 2
        return recent - previous > 0.05 ? "rising" : (recent - previous < -0.05 ? "falling" : "stable")
    }
}

/// Chest motion estimates use the Polar sample clock, independent of BLE packet batching.
struct ChestMotionSignal {
    private(set) var movementIntensity = 0.0
    private(set) var stillSeconds: TimeInterval = 0
    private(set) var breathingRate = 0.0
    private var lastTimestamp: UInt64?
    private var movementWindow: [Double] = []
    private var slowZ = 0.0
    private var fastZ = 0.0
    private var previous = 0.0
    private var beforePrevious = 0.0
    private var lastPeak: UInt64?
    private var intervals: [Double] = []

    mutating func feed(x: Double, y: Double, z: Double, timestamp: UInt64) {
        let dt = lastTimestamp.flatMap { timestamp > $0 ? Double(timestamp - $0) / 1e9 : nil }
        // Restart filters after a clock reset or a missing section of the stream.
        if dt == nil || dt! > 1 {
            self = ChestMotionSignal()
            slowZ = z
            fastZ = z
        }
        lastTimestamp = timestamp
        let movement = abs((x * x + y * y + z * z).squareRoot() - 1)
        movementWindow.append(movement)
        if movementWindow.count > 50 { movementWindow.removeFirst() }
        let average = movementWindow.reduce(0, +) / Double(movementWindow.count)
        movementIntensity = min(average / 0.5, 1)
        guard let dt, dt <= 1 else { return }
        stillSeconds = average > 0.05 ? 0 : stillSeconds + dt
        slowZ += (z - slowZ) * min(1, dt / 8)
        fastZ += (z - fastZ) * min(1, dt / 0.5)
        let breath = fastZ - slowZ
        if previous > beforePrevious, previous > breath, previous > 0.008 {
            if let lastPeak, timestamp > lastPeak {
                let interval = Double(timestamp - lastPeak) / 1e9
                if interval > 2, interval < 10 {
                    intervals.append(interval)
                    if intervals.count > 8 { intervals.removeFirst() }
                    breathingRate = 60 / (intervals.reduce(0, +) / Double(intervals.count))
                }
            }
            lastPeak = timestamp
        }
        if let lastPeak, timestamp > lastPeak, timestamp - lastPeak > 10_000_000_000 {
            intervals.removeAll()
            breathingRate = 0
        }
        beforePrevious = previous
        previous = breath
    }
}
