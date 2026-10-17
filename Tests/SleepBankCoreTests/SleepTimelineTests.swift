import XCTest
@testable import SleepBankCore

final class SleepTimelineTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_000_000)
    private func sample(_ start: Double, _ end: Double, _ stage: SleepTimeline.Stage, _ source: String) -> SleepTimeline.Sample {
        .init(start: t.addingTimeInterval(start * 3600), end: t.addingTimeInterval(end * 3600), stage: stage, source: source)
    }
    func testTwoTrackersDoNotDoubleSevenHourNight() {
        let result = SleepTimeline.resolve([sample(0, 7, .asleep, "oura"), sample(0, 7, .core, "watch")])
        XCTAssertEqual(result.reduce(0) { $0 + $1.duration }, 7 * 3600)
        XCTAssertEqual(result.map(\.stage), [.core])
    }
    func testAwakeStagesBeatOverlappingDurationOnlySleep() {
        let result = SleepTimeline.resolve([sample(0, 7, .asleep, "oura"), sample(0, 3, .core, "watch"),
                                            sample(3, 4, .awake, "watch"), sample(4, 7, .rem, "watch")])
        XCTAssertEqual(result.filter { $0.stage.isAsleep }.reduce(0) { $0 + $1.duration }, 6 * 3600)
        XCTAssertEqual(result.filter { $0.stage == .awake }.reduce(0) { $0 + $1.duration }, 3600)
    }
    func testFallbackFillsGapsAndClipsCrossingSamples() {
        let window = DateInterval(start: t, end: t.addingTimeInterval(7 * 3600))
        let result = SleepTimeline.resolve([sample(-2, 10, .asleep, "ring"), sample(1, 6, .core, "watch")], within: window)
        XCTAssertEqual(result.map(\.duration), [3600, 5 * 3600, 3600])
        XCTAssertEqual(result.first?.start, window.start)
        XCTAssertEqual(result.last?.end, window.end)
    }
    func testDuplicatesInBedAndQueryOrderCannotInflateStages() {
        let samples = [sample(0, 8, .inBed, "phone"), sample(1, 7, .core, "watch"),
                       sample(1, 7, .core, "watch"), sample(2, 3, .deep, "watch")]
        let result = SleepTimeline.resolve(samples)
        XCTAssertEqual(result, SleepTimeline.resolve(samples.reversed()))
        XCTAssertEqual(result.filter { $0.stage.isAsleep }.reduce(0) { $0 + $1.duration }, 6 * 3600)
        XCTAssertEqual(result.filter { $0.stage == .deep }.reduce(0) { $0 + $1.duration }, 3600)
        for (a, b) in zip(result, result.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start) }
    }
}
