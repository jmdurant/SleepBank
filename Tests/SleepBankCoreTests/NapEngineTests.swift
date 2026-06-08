import XCTest
@testable import SleepBankCore

final class NapEngineTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Onset detector

    func testOnsetDetectedWhenStillAndHeartRateDrops() {
        let detector = HeartRateImmobilityOnsetDetector()
        var onsetAt: Date?

        // 0–120s: quiet wake at 70 bpm, establishing baseline. Not yet still long enough.
        for s in stride(from: 0, through: 120, by: 5) {
            let t = t0.addingTimeInterval(TimeInterval(s))
            let sig = OnsetSignal(heartRate: 70, movementIntensity: 0.02, stillSeconds: TimeInterval(s))
            _ = detector.update(signal: sig, at: t)
        }
        // After baseline: HR drops to 64 (−6) and the wrist has been still > 90s.
        for s in stride(from: 125, through: 200, by: 5) {
            let t = t0.addingTimeInterval(TimeInterval(s))
            let sig = OnsetSignal(heartRate: 64, movementIntensity: 0.01, stillSeconds: TimeInterval(s))
            if detector.update(signal: sig, at: t) { onsetAt = t; break }
        }

        XCTAssertNotNil(onsetAt, "Onset should be detected once still and HR has dropped below baseline")
        XCTAssertEqual(detector.onsetTime, onsetAt)
    }

    func testNoOnsetWhileMoving() {
        let detector = HeartRateImmobilityOnsetDetector()
        var detected = false
        // HR drops, but stillSeconds never accumulates (user keeps moving).
        for s in stride(from: 0, through: 300, by: 5) {
            let t = t0.addingTimeInterval(TimeInterval(s))
            let hr = s < 120 ? 70 : 60
            let sig = OnsetSignal(heartRate: hr, movementIntensity: 0.4, stillSeconds: 0)
            if detector.update(signal: sig, at: t) { detected = true; break }
        }
        XCTAssertFalse(detected, "Onset must require sustained immobility, not just an HR drop")
    }

    func testHRVRiseCanTriggerOnsetWithMarginalHRDrop() {
        let detector = HeartRateImmobilityOnsetDetector()
        var onsetAt: Date?

        // Baseline window: HR 70, HRV (RMSSD) ~30 ms, settling.
        for s in stride(from: 0, through: 120, by: 5) {
            let t = t0.addingTimeInterval(TimeInterval(s))
            let sig = OnsetSignal(heartRate: 70, movementIntensity: 0.02,
                                  stillSeconds: TimeInterval(s), hrvRMSSD: 30)
            _ = detector.update(signal: sig, at: t)
        }
        // After baseline: HR barely moves (69, < 4 bpm drop) but HRV jumps to 55 ms
        // (+25 over baseline) while still — parasympathetic onset.
        for s in stride(from: 125, through: 200, by: 5) {
            let t = t0.addingTimeInterval(TimeInterval(s))
            let sig = OnsetSignal(heartRate: 69, movementIntensity: 0.01,
                                  stillSeconds: TimeInterval(s), hrvRMSSD: 55)
            if detector.update(signal: sig, at: t) { onsetAt = t; break }
        }
        XCTAssertNotNil(onsetAt, "A clear HRV rise should carry a marginal HR drop")
    }

    func testHRVRiseStillNeedsImmobility() {
        let detector = HeartRateImmobilityOnsetDetector()
        var detected = false
        for s in stride(from: 0, through: 250, by: 5) {
            let t = t0.addingTimeInterval(TimeInterval(s))
            let hrv: Double = s < 120 ? 30 : 60   // big HRV rise
            let sig = OnsetSignal(heartRate: 70, movementIntensity: 0.4,
                                  stillSeconds: 0, hrvRMSSD: hrv)
            if detector.update(signal: sig, at: t) { detected = true; break }
        }
        XCTAssertFalse(detected, "HRV rise alone, while moving, must not declare onset")
    }

    func testEEGOnsetTriggersWithoutCardiacChange() {
        let detector = HeartRateImmobilityOnsetDetector()
        var onsetAt: Date?
        // Flat HR, no HRV, but EEG reports high onset confidence while still.
        for s in stride(from: 0, through: 160, by: 5) {
            let t = t0.addingTimeInterval(TimeInterval(s))
            let sig = OnsetSignal(heartRate: 70, movementIntensity: 0.01,
                                  stillSeconds: TimeInterval(s), eegOnsetConfidence: 0.8)
            if detector.update(signal: sig, at: t) { onsetAt = t; break }
        }
        XCTAssertNotNil(onsetAt, "Confident EEG onset (with immobility) should declare onset")
    }

    func testEEGOnsetStillNeedsImmobility() {
        let detector = HeartRateImmobilityOnsetDetector()
        var detected = false
        for s in stride(from: 0, through: 200, by: 5) {
            let t = t0.addingTimeInterval(TimeInterval(s))
            let sig = OnsetSignal(heartRate: 70, movementIntensity: 0.5,
                                  stillSeconds: 0, eegOnsetConfidence: 0.9)
            if detector.update(signal: sig, at: t) { detected = true; break }
        }
        XCTAssertFalse(detected, "Even confident EEG onset must not fire while moving")
    }

    func testEngineWakesEarlyOnEEGDeepening() {
        let onset = t0.addingTimeInterval(120)
        let detector = StubOnsetDetector(onsetAfter: onset)
        let engine = NapEngine(type: .power, sessionStart: t0, detector: detector)

        _ = engine.tick(now: onset, signal: stillSignal)   // establish onset
        let target = onset.addingTimeInterval(NapType.power.targetWakeAfterOnset)

        // Well before the timer target, EEG flags deep sleep approaching.
        let deepening = OnsetSignal(heartRate: 58, movementIntensity: 0.01,
                                    stillSeconds: 300, eegDeepApproaching: true)
        let tick = engine.tick(now: onset.addingTimeInterval(60), signal: deepening)

        XCTAssertLessThan(onset.addingTimeInterval(60), target)
        XCTAssertTrue(tick.isAlarming)
        XCTAssertEqual(tick.wakeReason, .deepening)
    }

    func testOnsetDeclaredOnlyOnce() {
        let detector = HeartRateImmobilityOnsetDetector()
        var fireCount = 0
        for s in stride(from: 0, through: 400, by: 5) {
            let t = t0.addingTimeInterval(TimeInterval(s))
            let hr = s < 120 ? 70 : 62
            let sig = OnsetSignal(heartRate: hr, movementIntensity: 0.01, stillSeconds: TimeInterval(s))
            if detector.update(signal: sig, at: t) { fireCount += 1 }
        }
        XCTAssertEqual(fireCount, 1, "update() should return true exactly once")
    }

    // MARK: - Engine wake timing

    func testPowerNapWakesAtOnsetPlusTarget() {
        let detector = StubOnsetDetector(onsetAfter: t0.addingTimeInterval(300))
        let engine = NapEngine(type: .power, sessionStart: t0, detector: detector)

        // Drive to just after onset.
        let onset = t0.addingTimeInterval(300)
        _ = engine.tick(now: onset, signal: stillSignal)
        let afterOnset = engine.tick(now: onset.addingTimeInterval(1), signal: stillSignal)

        XCTAssertEqual(afterOnset.onsetTime, onset)
        XCTAssertEqual(afterOnset.wakeTarget, onset.addingTimeInterval(NapType.power.targetWakeAfterOnset))
        XCTAssertEqual(afterOnset.phase, .asleep)
        XCTAssertFalse(afterOnset.isAlarming)
    }

    func testWakeIsCappedAtCeilingForLateOnset() {
        // Onset at 20 min into a power nap: target would be 38 min, past the 30 min ceiling.
        let onset = t0.addingTimeInterval(20 * 60)
        let detector = StubOnsetDetector(onsetAfter: onset)
        let engine = NapEngine(type: .power, sessionStart: t0, detector: detector)

        _ = engine.tick(now: onset, signal: stillSignal)
        let tick = engine.tick(now: onset.addingTimeInterval(1), signal: stillSignal)

        XCTAssertEqual(tick.wakeTarget, engine.ceiling, "Wake must never exceed the safety ceiling")
    }

    func testAlarmFiresAtTargetWhenOnsetKnown() {
        let onset = t0.addingTimeInterval(120)
        let detector = StubOnsetDetector(onsetAfter: onset)
        let engine = NapEngine(type: .power, sessionStart: t0, detector: detector)

        _ = engine.tick(now: onset, signal: stillSignal)
        let target = onset.addingTimeInterval(NapType.power.targetWakeAfterOnset)

        let before = engine.tick(now: target.addingTimeInterval(-1), signal: stillSignal)
        XCTAssertFalse(before.isAlarming)

        let at = engine.tick(now: target, signal: stillSignal)
        XCTAssertTrue(at.isAlarming)
        XCTAssertEqual(at.wakeReason, .reachedTarget)
        XCTAssertEqual(at.phase, .waking)
    }

    func testCeilingFiresAlarmWhenOnsetNeverDetected() {
        let detector = StubOnsetDetector(onsetAfter: nil)   // never detects onset
        let engine = NapEngine(type: .power, sessionStart: t0, detector: detector)

        let before = engine.tick(now: engine.ceiling.addingTimeInterval(-1), signal: movingSignal)
        XCTAssertFalse(before.isAlarming)
        XCTAssertNil(before.onsetTime)

        let at = engine.tick(now: engine.ceiling, signal: movingSignal)
        XCTAssertTrue(at.isAlarming, "Alarm must fire at the ceiling even with no detected onset")
        XCTAssertEqual(at.wakeReason, .ceiling)
    }

    func testCountdownTracksCeilingBeforeOnset() throws {
        let detector = StubOnsetDetector(onsetAfter: nil)
        let engine = NapEngine(type: .power, sessionStart: t0, detector: detector)
        let tick = engine.tick(now: t0.addingTimeInterval(60), signal: movingSignal)
        let until = try XCTUnwrap(tick.timeUntilWake)
        XCTAssertEqual(until, NapType.power.maxSessionDuration - 60, accuracy: 0.001)
    }

    // MARK: - Fixtures

    private var stillSignal: OnsetSignal {
        OnsetSignal(heartRate: 60, movementIntensity: 0.01, stillSeconds: 200)
    }
    private var movingSignal: OnsetSignal {
        OnsetSignal(heartRate: 72, movementIntensity: 0.3, stillSeconds: 0)
    }
}

/// Test double that declares onset at a fixed time, decoupling engine tests from
/// the detector heuristic.
private final class StubOnsetDetector: SleepOnsetDetector {
    private let onsetAfter: Date?
    private(set) var onsetTime: Date?
    init(onsetAfter: Date?) { self.onsetAfter = onsetAfter }
    func update(signal: OnsetSignal, at time: Date) -> Bool {
        guard onsetTime == nil, let target = onsetAfter, time >= target else { return false }
        onsetTime = time
        return true
    }
    func reset() { onsetTime = nil }
}
