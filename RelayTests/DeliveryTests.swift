import XCTest
@testable import RelayReliability

final class DeliveryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCommandFallbackIsIdempotentAcrossRelaunch() {
        let payload: [String: Any] = ["watchHRMirror": true, "commandID": UUID().uuidString, "issuedAt": now.timeIntervalSince1970, "expiresAt": now.addingTimeInterval(30).timeIntervalSince1970]
        var ledger = RelayCommandLedger()
        XCTAssertEqual(ledger.receive(payload, now: now), .accepted)
        var restored = RelayCommandLedger(handled: ledger.handled)
        XCTAssertEqual(restored.receive(payload, now: now), .duplicate)
        var offline = RelayCommandLedger()
        XCTAssertEqual(offline.receive(payload, now: now.addingTimeInterval(31)), .expired)
        XCTAssertTrue(offline.handled.isEmpty)
    }
    func testDelayedStartCannotOverrideANewerStopEvenAfterRelaunch() {
        var ledger = RelayCommandLedger()
        let stop: [String: Any] = ["watchHRMirror": false, "commandID": UUID().uuidString, "issuedAt": now.timeIntervalSince1970, "expiresAt": now.addingTimeInterval(30).timeIntervalSince1970]
        XCTAssertEqual(ledger.receive(stop, now: now), .accepted)
        var restored = RelayCommandLedger(handled: ledger.handled, latestIssuedAt: ledger.latestIssuedAt)
        let lateStart: [String: Any] = ["watchHRMirror": true, "commandID": UUID().uuidString, "issuedAt": now.addingTimeInterval(-1).timeIntervalSince1970, "expiresAt": now.addingTimeInterval(29).timeIntervalSince1970]
        XCTAssertEqual(restored.receive(lateStart, now: now), .superseded)
    }
    func testMalformedCommandCannotExecute() {
        var ledger = RelayCommandLedger()
        XCTAssertEqual(ledger.receive(["startWorkout": "walk"], now: now), .invalid)
        XCTAssertEqual(ledger.receive(["watchHRMirror": true, "commandID": UUID().uuidString, "issuedAt": now.timeIntervalSince1970, "expiresAt": now.addingTimeInterval(3600).timeIntervalSince1970], now: now), .invalid)
    }
    func testTraceSurvivesRestartAndUnrelatedOrDuplicateAcknowledgements() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID(), data = Data("completed nap trace".utf8)
        try RelayFileOutbox(directory: directory).save(id: id, data: data)
        let restarted = RelayFileOutbox(directory: directory)
        XCTAssertEqual(restarted.pending.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restarted.pending.first)), data)
        try restarted.acknowledge(UUID())
        XCTAssertEqual(restarted.pending.count, 1)
        try restarted.acknowledge(id)
        try restarted.acknowledge(id)
        XCTAssertTrue(restarted.pending.isEmpty)
    }
    func testWriteFailureDoesNotCreateAFalsePendingReceipt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        let outbox = RelayFileOutbox(directory: file)
        XCTAssertThrowsError(try outbox.save(id: UUID(), data: Data()))
        XCTAssertTrue(outbox.pending.isEmpty)
    }
    func testOldNapEventsCannotRestartOrStopANewerNap() {
        var state = NapRelayState()
        let id = UUID().uuidString
        func event(_ kind: String, sequence: Int, id: String, at: Date) -> [String: Any] {
            ["napID": id, "napStartedAt": at.timeIntervalSince1970, "eventAt": at.timeIntervalSince1970, "sequence": sequence, "napEvent": kind]
        }
        XCTAssertTrue(state.receive(event("start", sequence: 1, id: id, at: now), now: now))
        XCTAssertFalse(state.receive(event("start", sequence: 1, id: id, at: now), now: now))
        XCTAssertTrue(state.receive(event("end", sequence: 2, id: id, at: now), now: now))
        XCTAssertFalse(state.receive(event("update", sequence: 3, id: id, at: now), now: now))
        let newer = UUID().uuidString
        XCTAssertTrue(state.receive(event("start", sequence: 1, id: newer, at: now.addingTimeInterval(1)), now: now.addingTimeInterval(1)))
        XCTAssertFalse(state.receive(event("end", sequence: 4, id: id, at: now), now: now.addingTimeInterval(1)))
    }
    func testDelayedStartDoesNotStartSensorsAfterNapHasFinished() {
        var state = NapRelayState()
        let payload: [String: Any] = ["napID": UUID().uuidString, "napStartedAt": now.timeIntervalSince1970, "eventAt": now.timeIntervalSince1970, "sequence": 1, "napEvent": "start"]
        XCTAssertFalse(state.receive(payload, now: now.addingTimeInterval(120)))
    }
}
