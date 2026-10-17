import Foundation
import XCTest
@testable import SensorProcessingCore

final class SensorQualityTests: XCTestCase {
    func testFreshnessRejectsExpiredMissingAndFutureSamples() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(SensorFreshness.isFresh(now.addingTimeInterval(-30), within: 30, now: now))
        XCTAssertFalse(SensorFreshness.isFresh(now.addingTimeInterval(-31), within: 30, now: now))
        XCTAssertFalse(SensorFreshness.isFresh(now.addingTimeInterval(1), within: 30, now: now))
        XCTAssertFalse(SensorFreshness.isFresh(nil, within: 30, now: now))
        XCTAssertTrue(SensorFreshness.isFresh(now.addingTimeInterval(-120), within: SensorFreshness.temperature, now: now))
    }

    func testTemperatureBaselineRequiresConsecutiveConfidentValidReadings() {
        var series = TemperatureSeries()
        series.append(36, confidence: 90, valid: true)
        series.append(36, confidence: 90, valid: true)
        series.append(50, confidence: 90, valid: false)
        series.append(37, confidence: 90, valid: true)
        XCTAssertNil(series.baseline)
        series.append(37, confidence: 80, valid: true)
        series.append(38, confidence: 90, valid: true)
        series.append(38, confidence: 90, valid: true)
        XCTAssertNil(series.baseline)
        series.append(38, confidence: 90, valid: true)
        XCTAssertEqual(series.baseline, 38)
        XCTAssertEqual(series.peak, 38)
        XCTAssertFalse(series.values.contains(50))
    }

    func testTemperaturePeakDoesNotWaitForBaselineAndNonfiniteValuesAreExcluded() {
        var series = TemperatureSeries()
        series.append(38.5, confidence: 90, valid: true)
        XCTAssertEqual(series.peak, 38.5)
        XCTAssertNil(series.baseline)
        series.append(.nan, confidence: 90, valid: true)
        series.append(39, confidence: .infinity, valid: true)
        XCTAssertEqual(series.values, [38.5])
    }

    func testTrendNeedsTwoSeparatePairsAndHistoryIsBounded() {
        var series = TemperatureSeries()
        for _ in 0..<3 { series.append(37, confidence: 90, valid: true) }
        XCTAssertEqual(series.trend, "stable")
        series.append(38, confidence: 90, valid: true)
        XCTAssertEqual(series.trend, "rising")
        for _ in 0..<35 { series.append(36, confidence: 90, valid: true) }
        XCTAssertEqual(series.values.count, 30)
        XCTAssertEqual(series.trend, "stable")
        XCTAssertEqual(series.delta, -1)
    }

    func testBatchedAccelerometerUsesSensorTimeForStillness() {
        var motion = ChestMotionSignal()
        // Simulate five seconds delivered in one callback, with no wall-clock wait.
        for index in 0...1000 {
            motion.feed(x: 0, y: 0, z: 1, timestamp: 100_000_000_000 + UInt64(index) * 5_000_000)
        }
        XCTAssertEqual(motion.stillSeconds, 5, accuracy: 0.0001)
        XCTAssertEqual(motion.breathingRate, 0)
        motion.feed(x: 0, y: 0, z: 1, timestamp: 200_000_000_000)
        XCTAssertEqual(motion.stillSeconds, 0, "A missing section must not count as still time")
        motion.feed(x: 0, y: 0, z: 1, timestamp: 1)
        XCTAssertEqual(motion.stillSeconds, 0, "Clock resets must not underflow UInt64")
    }

    func testSyntheticChestOscillationRecoversRateAndExpiresAfterFlatSignal() {
        var motion = ChestMotionSignal()
        for index in 0...12000 {
            let seconds = Double(index) / 100
            let z = 1 + 0.03 * sin(2 * Double.pi * seconds / 4)
            motion.feed(x: 0, y: 0, z: z, timestamp: UInt64(index) * 10_000_000)
        }
        XCTAssertEqual(motion.breathingRate, 15, accuracy: 0.2)
        for index in 12001...18000 {
            motion.feed(x: 0, y: 0, z: 1, timestamp: UInt64(index) * 10_000_000)
        }
        XCTAssertEqual(motion.breathingRate, 0)
    }
}

final class EEGFrameTests: XCTestCase {
    private func frame(frequency: Double) -> [Float] {
        (0..<256).map { 2048 + Float(100 * sin(2 * Double.pi * frequency * Double($0) / 256)) }
    }

    private func feed(_ processor: EEGSleepProcessor, samples: [Float], packetSize: Int) {
        for start in stride(from: 0, to: samples.count, by: packetSize) {
            for channel in 0..<4 {
                processor.feedSamples(channel: channel, samples: Array(samples[start..<min(samples.count, start + packetSize)]))
            }
        }
    }

    func testEEGResultsDoNotDependOnBLEPacketSize() {
        let packeted = EEGSleepProcessor()
        let framed = EEGSleepProcessor()
        // A spectrum change inside baseline acquisition must not be accelerated by small packets.
        for second in 0..<40 {
            let samples = frame(frequency: second < 20 ? 10 : 6)
            feed(packeted, samples: samples, packetSize: 12)
            feed(framed, samples: samples, packetSize: 256)
        }
        XCTAssertTrue(packeted.hasGoodSignal)
        XCTAssertEqual(packeted.processedFrameCount, 40)
        XCTAssertEqual(framed.processedFrameCount, 40)
        XCTAssertEqual(packeted.onsetIndex, framed.onsetIndex, accuracy: 0.0001)
        XCTAssertEqual(packeted.onsetDetected, framed.onsetDetected)
        XCTAssertEqual(packeted.avgPowers.theta, framed.avgPowers.theta, accuracy: 0.0001)
    }

    func testEEGResetClearsContactSpectrumAndTrace() {
        let processor = EEGSleepProcessor()
        feed(processor, samples: frame(frequency: 10), packetSize: 12)
        XCTAssertTrue(processor.hasGoodSignal)
        XCTAssertGreaterThan(processor.avgPowers.alpha, 0)
        processor.reset()
        XCTAssertFalse(processor.hasGoodSignal)
        XCTAssertNil(processor.lastFrameDate)
        XCTAssertEqual(processor.processedFrameCount, 0)
        XCTAssertEqual(processor.channelQuality, [0, 0, 0, 0])
        XCTAssertEqual(processor.avgPowers.alpha, 0)
        XCTAssertEqual(processor.spindlePower, 0)
        XCTAssertTrue(processor.traceSamples.isEmpty)
    }

    func testEEGWaitsForEveryChannelAndClearsFlagsOnArtifacts() {
        let processor = EEGSleepProcessor()
        for channel in 0..<3 { processor.feedSamples(channel: channel, samples: frame(frequency: 10)) }
        XCTAssertFalse(processor.hasGoodSignal)
        processor.feedSamples(channel: 3, samples: frame(frequency: 10))
        XCTAssertTrue(processor.hasGoodSignal)
        XCTAssertEqual(processor.processedFrameCount, 1)
        processor.onsetDetected = true
        processor.deepSleepApproaching = true
        feed(processor, samples: Array(repeating: 4095, count: 256), packetSize: 12)
        XCTAssertFalse(processor.hasGoodSignal)
        XCTAssertFalse(processor.onsetDetected)
        XCTAssertFalse(processor.deepSleepApproaching)
    }
}
