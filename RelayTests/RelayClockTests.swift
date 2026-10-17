import XCTest
@testable import RelayReliability

final class RelayClockTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMotionTrafficCannotRefreshAnOldHeartRateClock() {
        let hrAt = now.addingTimeInterval(-11)
        XCTAssertTrue(RelayTimestamp.isFresh(now, now: now))
        XCTAssertFalse(RelayTimestamp.isFresh(hrAt, now: now))
        XCTAssertFalse(RelayTimestamp.accepts(hrAt, after: nil, now: now))
    }
    func testDuplicateOutOfOrderFutureAndMissingSamplesAreRejected() {
        XCTAssertFalse(RelayTimestamp.accepts(now, after: now, now: now))
        XCTAssertFalse(RelayTimestamp.accepts(now.addingTimeInterval(-1), after: now, now: now))
        XCTAssertFalse(RelayTimestamp.accepts(now.addingTimeInterval(60), after: nil, now: now))
        XCTAssertFalse(RelayTimestamp.accepts(nil, after: nil, now: now))
        XCTAssertTrue(RelayTimestamp.accepts(now, after: now.addingTimeInterval(-1), now: now))
        XCTAssertNil(RelayTimestamp.date(Double.nan))
    }
    func testBackgroundWorkStaysPendingUntilEveryModelWriteFinishes() {
        let tracker = RelayWorkTracker()
        tracker.begin(); tracker.begin()
        tracker.end()
        XCTAssertFalse(tracker.isIdle)
        tracker.end()
        XCTAssertTrue(tracker.isIdle)
    }
}
