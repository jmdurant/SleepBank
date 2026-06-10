import XCTest
@testable import SleepBankCore

final class SleepScoreTests: XCTestCase {

    func testFullEfficientNightScoresHigh() {
        let s = SleepScore.score(asleepHours: 8, needHours: 7.5, efficiency: 0.97)
        XCTAssertGreaterThanOrEqual(s, 95)
        XCTAssertEqual(SleepScore.label(s), "Very High")
    }

    func testShortNightScoresLow() {
        let s = SleepScore.score(asleepHours: 4, needHours: 7.5, efficiency: 0.9)
        XCTAssertLessThan(s, 50)
    }

    /// The bug that started this: ~5h50m used to score 95 because we graded against
    /// the user's own short average. Apple gave 71; anchored at the fixed 7h50m mark
    /// we should now land in the same neighbourhood (a little high — we don't yet
    /// score bedtime consistency), and nowhere near 95.
    func testRealShortNightTracksApple() {
        let s = SleepScore.score(asleepHours: 5.0 + 50.0/60.0, needHours: 6, efficiency: 0.94)
        XCTAssertGreaterThanOrEqual(s, 68)
        XCTAssertLessThanOrEqual(s, 82)
        XCTAssertLessThan(s, 90)   // never "Very High" for under 6 hours
    }

    func testChronicShortAverageDoesNotInflateScore() {
        // Even if the user's "need" comes in low, full credit still requires ~7h50m.
        let lowNeed = SleepScore.score(asleepHours: 6, needHours: 6, efficiency: 0.97)
        XCTAssertLessThan(lowNeed, 90)
    }

    func testDurationDominatesButEfficiencyMatters() {
        let solid = SleepScore.score(asleepHours: 7, needHours: 7.5, efficiency: 0.95)
        let fragmented = SleepScore.score(asleepHours: 7, needHours: 7.5, efficiency: 0.70)
        XCTAssertGreaterThan(solid, fragmented)
    }

    func testDurationCreditCapsAtFullMark() {
        let full = SleepScore.score(asleepHours: 8, needHours: 7.5, efficiency: 1)
        let oversleep = SleepScore.score(asleepHours: 10, needHours: 7.5, efficiency: 1)
        XCTAssertEqual(full, oversleep)   // past the full-credit mark, no extra credit
        XCTAssertEqual(oversleep, 100)
    }

    func testLowDeepAndRemDockDuration() {
        // Same hours, but a stage-poor night loses up to 5 each for low Deep/REM.
        let healthy = SleepScore.components(asleepHours: 7, needHours: 7.5, efficiency: 0.95,
                                            deepHours: 7 * 0.15, remHours: 7 * 0.22)
        let stagePoor = SleepScore.components(asleepHours: 7, needHours: 7.5, efficiency: 0.95,
                                              deepHours: 7 * 0.04, remHours: 7 * 0.08)
        XCTAssertGreaterThan(healthy.duration, stagePoor.duration)
        XCTAssertLessThanOrEqual(healthy.duration - stagePoor.duration, 10)   // capped at −5/−5
    }

    func testNoStageDataMeansNoStagePenalty() {
        // Basic trackers report no stages — don't penalise what they can't measure.
        let p = SleepScore.durationPoints(asleepHours: 7, needHours: 7.5)
        let withZeroStages = p - SleepScore.stagePenalty(asleepHours: 7, deepHours: 0, remHours: 0)
        XCTAssertEqual(withZeroStages, p, accuracy: 0.001)
    }

    func testScatteredScheduleCannotScorePerfectConsistency() {
        // Even bang on the median, a scattered recent history docks consistency.
        let onMedianRegular = SleepScore.consistencyPoints(bedtimeMinutes: 300, normalMinutes: 300, spreadMinutes: 10)
        let onMedianScattered = SleepScore.consistencyPoints(bedtimeMinutes: 300, normalMinutes: 300, spreadMinutes: 75)
        XCTAssertEqual(onMedianRegular, 30, accuracy: 0.01)
        XCTAssertLessThan(onMedianScattered, 27)
    }

    func testConsistencyGivesGraceThenPenalizesLateNights() {
        XCTAssertEqual(SleepScore.consistencyPoints(bedtimeMinutes: 300, normalMinutes: 300), 30, accuracy: 0.01)   // on time
        XCTAssertEqual(SleepScore.consistencyPoints(bedtimeMinutes: 315, normalMinutes: 300), 30, accuracy: 0.01)   // 15 min grace
        XCTAssertEqual(SleepScore.consistencyPoints(bedtimeMinutes: 360, normalMinutes: 300), 20, accuracy: 0.5)    // +1h → ~−10
        XCTAssertEqual(SleepScore.consistencyPoints(bedtimeMinutes: 450, normalMinutes: 300), 0, accuracy: 0.01)    // +2.5h → 0
    }

    func testConsistencyIsLenientWhenEarlyAndWrapsMidnight() {
        XCTAssertEqual(SleepScore.consistencyPoints(bedtimeMinutes: 240, normalMinutes: 300), 30, accuracy: 0.01)   // 1h early, free
        XCTAssertLessThan(SleepScore.consistencyPoints(bedtimeMinutes: 120, normalMinutes: 300), 30)               // 3h early, mild
        // 00:30 vs a 23:00 normal in raw clock-minutes is +90, not −1350.
        XCTAssertEqual(SleepScore.consistencyPoints(bedtimeMinutes: 30, normalMinutes: 1380),
                       SleepScore.consistencyPoints(bedtimeMinutes: 390, normalMinutes: 300), accuracy: 0.01)
    }

    func testConsistencyRaisesScoreToFull100Scale() {
        // With consistency data a perfect night reaches 100; the same night without
        // it tops out lower (the measured 70 rescaled never beats a fully-graded 100).
        let graded = SleepScore.score(asleepHours: 8, needHours: 7.5, efficiency: 1,
                                      bedtimeMinutes: 300, normalMinutes: 300)
        XCTAssertEqual(graded, 100)
    }

    func testDebtFromScoreIsMonotonicAndClamped() {
        XCTAssertEqual(SleepScore.debt(fromScore: 100), 0.05, accuracy: 0.001)
        XCTAssertEqual(SleepScore.debt(fromScore: 0), 0.9, accuracy: 0.001)
        XCTAssertLessThan(SleepScore.debt(fromScore: 90), SleepScore.debt(fromScore: 60))
    }

    func testHoursDebtMatchesTheSimpleRule() {
        XCTAssertEqual(SleepScore.debt(asleepHours: 7.5, needHours: 7.5), 0.05, accuracy: 0.001)
        XCTAssertEqual(SleepScore.debt(asleepHours: 5, needHours: 7.5), 1 - 5/7.5, accuracy: 0.001)
        XCTAssertEqual(SleepScore.debt(asleepHours: 0, needHours: 7.5), 0.9, accuracy: 0.001)
    }
}
