import XCTest
import SleepBankCore
@testable import SleepBank

@MainActor
final class WatchRelayTests: XCTestCase {
    func testRepeatedWatchPacketDoesNotDuplicateOrRedateHeartRateHistory() {
        let receiver = WatchHRService()
        receiver.requestStart()
        defer { receiver.requestStop() }
        let now = Date()
        receiver.update(bpm: 64, heartRateAt: now, movement: 0.1, stillSeconds: 0, motionAt: now, now: now)
        receiver.update(bpm: 64, heartRateAt: now, movement: 0.2, stillSeconds: 0, motionAt: now.addingTimeInterval(2), now: now.addingTimeInterval(2))
        XCTAssertEqual(receiver.heartRateHistory.count, 1)
        XCTAssertEqual(receiver.heartRateHistory.first?.timestamp, now)
        XCTAssertEqual(receiver.movementIntensity, 0.2)
        receiver.update(bpm: 99, heartRateAt: now.addingTimeInterval(-1), movement: nil, stillSeconds: nil, motionAt: nil, now: now)
        XCTAssertEqual(receiver.currentHeartRate, 64)
    }
    func testStopRejectsInFlightSamplesAndClearsFreshness() {
        let receiver = WatchHRService()
        receiver.requestStart()
        let now = Date()
        receiver.update(bpm: 64, heartRateAt: now, movement: 0, stillSeconds: 5, motionAt: now, now: now)
        XCTAssertEqual(receiver.freshHeartRate, 64)
        receiver.requestStop()
        receiver.update(bpm: 70, heartRateAt: now.addingTimeInterval(1), movement: 0, stillSeconds: 6, motionAt: now.addingTimeInterval(1), now: now.addingTimeInterval(1))
        XCTAssertNil(receiver.freshHeartRate)
        XCTAssertFalse(receiver.isStreaming)
        XCTAssertEqual(receiver.heartRateHistory.count, 1)
    }
    func testLiveActivityExpiryUsesSampleTime() {
        let at = Date().addingTimeInterval(-30)
        let state = NapActivityAttributes.ContentState(phase: "asleep", wakeTarget: Date().addingTimeInterval(60), heartRate: 60, onsetDetected: true, heartRateAt: at)
        XCTAssertEqual(state.staleDate, at.addingTimeInterval(10))
        XCTAssertLessThan(state.staleDate, Date())
    }
    func testTraceAcknowledgementRequiresDiskPersistenceAndImportsAreIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("naps.json")
        let record = NapDecisionRecord(id: UUID(), type: .power, start: Date().addingTimeInterval(-600), end: Date(), onset: nil, onsetTrigger: nil, wakeReason: nil, epochs: [])
        let store = NapDecisionStore(url: url)
        XCTAssertTrue(store.add(record))
        XCTAssertTrue(store.add(record))
        XCTAssertEqual(NapDecisionStore(url: url).records.count, 1)
        let unavailable = NapDecisionStore(url: directory.appendingPathComponent("missing/naps.json"))
        XCTAssertFalse(unavailable.add(record))
        XCTAssertTrue(unavailable.records.isEmpty)
    }

}
