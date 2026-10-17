import XCTest
@testable import SleepBank

@MainActor
final class PhoneAlarmServiceTests: XCTestCase {
    final class Alarm: SystemWakeAlarm {
        var authorized = true
        var alerting = false
        var scheduled: [(UUID, Date)] = []
        var cancelled: [UUID] = []
        var authorizationWait: CheckedContinuation<Bool, Never>?
        var holdAuthorization = false
        var failScheduling = false
        func authorize() async throws -> Bool {
            if holdAuthorization { return await withCheckedContinuation { authorizationWait = $0 } }
            return authorized
        }
        func schedule(id: UUID, at: Date, napTitle: String) async throws {
            if failScheduling { throw NSError(domain: "test", code: 1) }
            scheduled.append((id, at))
        }
        func isAlerting(id: UUID) -> Bool { alerting }
        func cancel(id: UUID) { cancelled.append(id) }
    }
    final class Output: PhoneWakeOutput {
        var pulses = 0; var pauses = 0; var stops = 0
        func pulse(elapsed: TimeInterval) { pulses += 1 }
        func pause() { pauses += 1 }
        func stop() { stops += 1 }
    }
    func testEarlyWakeSoundsImmediatelyDespiteArmedFutureAlarm() async {
        let system = Alarm(), output = Output()
        let service = PhoneAlarmService(system: system, output: output)
        await service.scheduleWake(at: Date().addingTimeInterval(600), napTitle: "Power Nap")
        XCTAssertTrue(service.systemAlarmArmed)
        service.start()
        XCTAssertEqual(output.pulses, 1)
        for _ in 0..<20 where system.scheduled.count < 2 { await Task.yield() }
        XCTAssertEqual(system.scheduled.count, 2)
        XCTAssertLessThan(system.scheduled.last!.1.timeIntervalSinceNow, 3)
        XCTAssertTrue(system.cancelled.contains(system.scheduled[0].0))
        service.stop()
    }
    func testActuallyAlertingSystemAlarmSuppressesDuplicateAudio() async {
        let system = Alarm(), output = Output()
        let service = PhoneAlarmService(system: system, output: output)
        await service.scheduleWake(at: Date().addingTimeInterval(600), napTitle: "Nap")
        system.alerting = true
        service.start()
        XCTAssertEqual(output.pulses, 0)
        XCTAssertEqual(output.pauses, 1)
        service.stop()
    }
    func testDeniedAuthorizationStillSoundsFallback() async {
        let system = Alarm(), output = Output(); system.authorized = false
        let service = PhoneAlarmService(system: system, output: output)
        await service.scheduleWake(at: Date().addingTimeInterval(600), napTitle: "Nap")
        service.start()
        XCTAssertEqual(output.pulses, 1)
        service.stop()
    }
    func testFailedReplacementKeepsSafetyAlarm() async {
        let system = Alarm(), output = Output()
        let service = PhoneAlarmService(system: system, output: output)
        await service.scheduleWake(at: Date().addingTimeInterval(600), napTitle: "Nap")
        system.failScheduling = true
        await service.scheduleWake(at: Date().addingTimeInterval(300), napTitle: "Nap")
        XCTAssertTrue(service.systemAlarmArmed)
        XCTAssertTrue(system.cancelled.isEmpty)
        service.stop()
    }
    func testStopDuringAuthorizationCannotLeaveAnOrphanAlarm() async {
        let system = Alarm(), output = Output(); system.holdAuthorization = true
        let service = PhoneAlarmService(system: system, output: output)
        let task = Task { await service.scheduleWake(at: Date().addingTimeInterval(600), napTitle: "Nap") }
        for _ in 0..<20 where system.authorizationWait == nil { await Task.yield() }
        service.stop()
        system.authorizationWait?.resume(returning: true)
        await task.value
        XCTAssertTrue(system.scheduled.isEmpty)
        XCTAssertFalse(service.systemAlarmArmed)
    }
}
