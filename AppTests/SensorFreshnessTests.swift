import XCTest
@testable import SleepBank

@MainActor
final class SensorFreshnessTests: XCTestCase {
    func testH10ExpiresAndDisconnectClearsReadings() {
        var now = Date()
        let h10 = PolarH10Service(now: { now })
        h10.isConnected = true
        h10.receiveHeartRate(bpm: 64, rr: [900, 950, 900, 950, 900, 950, 900, 950, 900, 950])
        XCTAssertEqual(h10.freshHeartRate, 64)
        XCTAssertNotNil(h10.freshHRV)
        now = now.addingTimeInterval(11)
        XCTAssertNil(h10.freshHeartRate); XCTAssertNil(h10.freshHRV)
        h10.receiveHeartRate(bpm: 65, rr: [])
        XCTAssertEqual(h10.freshHeartRate, 65)
        XCTAssertNil(h10.freshHRV, "New HR cannot refresh old RR data")
        h10.disconnect()
        XCTAssertNil(h10.freshHeartRate)
        XCTAssertEqual(h10.currentHeartRate, 0)
        XCTAssertEqual(h10.hrvRMSSD, 0)
    }
    func testMotionGapDoesNotCountAsStillness() {
        var now = Date()
        let h10 = PolarH10Service(now: { now }); h10.isConnected = true
        h10.feedAccel(x: 0, y: 0, z: 1); h10.isAccStreaming = true
        now = now.addingTimeInterval(1)
        h10.feedAccel(x: 0, y: 0, z: 1)
        XCTAssertEqual(h10.stillSeconds, 1, accuracy: 0.001)
        now = now.addingTimeInterval(60)
        XCTAssertFalse(h10.hasFreshMotion)
        h10.feedAccel(x: 0, y: 0, z: 1)
        XCTAssertEqual(h10.stillSeconds, 0)
    }
    func testMuseRequiresFreshPacketsAndResetsOnDisconnect() {
        let muse = MuseService()
        muse.isConnected = true; muse.isStreaming = true
        for channel in 0..<4 { muse.parseEEGPacket(Data(repeating: 0, count: 20), channel: channel) }
        muse.eeg.hasGoodSignal = true; muse.eeg.onsetIndex = 0.9; muse.eeg.deepSleepApproaching = true
        XCTAssertTrue(muse.hasFreshEEG)
        muse.disconnect()
        XCTAssertFalse(muse.hasFreshEEG)
        XCTAssertFalse(muse.eeg.hasGoodSignal)
        XCTAssertEqual(muse.eeg.onsetIndex, 0)
        XCTAssertFalse(muse.eeg.deepSleepApproaching)
    }
    func testMuseRejectsStalePacketsEvenWithGoodContact() {
        let muse = MuseService(); muse.isConnected = true; muse.isStreaming = true
        for channel in 0..<4 {
            muse.parseEEGPacket(Data(repeating: 0, count: 20), channel: channel, at: Date().addingTimeInterval(-10))
        }
        muse.eeg.hasGoodSignal = true
        XCTAssertFalse(muse.hasFreshEEG)
    }
}
