import XCTest
@testable import SleepBankCore

final class IntervalsTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }

    func testAllowedWindowSplitsABusyBlock() {
        // Patient 13:00–14:30 (here 0–90), OK-to-nap 13:20–14:00 (20–60).
        let busy = [DateInterval(start: at(0), end: at(90))]
        let allowed = [DateInterval(start: at(20), end: at(60))]
        let result = Intervals.subtract(allowed, from: busy)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], DateInterval(start: at(0), end: at(20)))
        XCTAssertEqual(result[1], DateInterval(start: at(60), end: at(90)))
    }

    func testAllowedCoveringBusyRemovesIt() {
        let busy = [DateInterval(start: at(30), end: at(60))]
        let allowed = [DateInterval(start: at(0), end: at(120))]
        XCTAssertTrue(Intervals.subtract(allowed, from: busy).isEmpty)
    }

    func testAllowedTrimsAnEdge() {
        let busy = [DateInterval(start: at(0), end: at(60))]
        let allowed = [DateInterval(start: at(40), end: at(80))]   // overlaps the tail
        let result = Intervals.subtract(allowed, from: busy)
        XCTAssertEqual(result, [DateInterval(start: at(0), end: at(40))])
    }

    func testNonOverlappingAllowedLeavesBusyUntouched() {
        let busy = [DateInterval(start: at(0), end: at(30))]
        let allowed = [DateInterval(start: at(60), end: at(90))]
        XCTAssertEqual(Intervals.subtract(allowed, from: busy), busy)
    }

    func testEmptyAllowedIsIdentity() {
        let busy = [DateInterval(start: at(0), end: at(30))]
        XCTAssertEqual(Intervals.subtract([], from: busy), busy)
    }
}
