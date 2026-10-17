import XCTest
@testable import SleepBankCore

final class PlanReminderTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "SleepBankReminderTests.\(UUID())"; defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func testTwoWalksAndTwoNapsSurviveRestartAndIndependentCancellation() {
        let store = PlanReminderStore(defaults: defaults)
        let items = [PlanReminder.Kind.walk, .walk, .nap, .nap].enumerated().map { index, kind in
            PlanReminder(id: UUID(), kind: kind, at: Date().addingTimeInterval(Double(index + 1) * 3600))
        }
        items.forEach(store.upsert)
        let restarted = PlanReminderStore(defaults: defaults)
        XCTAssertEqual(Set(restarted.all().map(\.id)), Set(items.map(\.id)))
        XCTAssertEqual(Set(items.map(\.notificationID)).count, 4)
        restarted.remove(id: items[0].id)
        XCTAssertEqual(Set(restarted.all().map(\.id)), Set(items.dropFirst().map(\.id)))
    }
    func testRescheduleReplacesOnlySameIDAcrossDays() {
        let store = PlanReminderStore(defaults: defaults)
        let a = PlanReminder(id: UUID(), kind: .walk, at: Date())
        let b = PlanReminder(id: UUID(), kind: .walk, at: Date().addingTimeInterval(86400))
        store.upsert(a); store.upsert(b)
        let moved = PlanReminder(id: a.id, kind: .walk, at: Date().addingTimeInterval(172800))
        store.upsert(moved)
        XCTAssertEqual(store.all().count, 2)
        XCTAssertTrue(store.all().contains(b)); XCTAssertTrue(store.all().contains(moved))
    }
    func testLegacyRemindersMigrateOnceWithCancellableIdentifiers() throws {
        defaults.set(Date().timeIntervalSinceReferenceDate, forKey: "scheduledNapAt")
        defaults.set("cycle", forKey: "scheduledNapType")
        let store = PlanReminderStore(defaults: defaults)
        let nap = try XCTUnwrap(store.all().first)
        XCTAssertEqual(nap.napType, .cycle)
        XCTAssertEqual(nap.legacyNotificationID, "scheduledNap")
        XCTAssertEqual(store.all().first?.id, nap.id)
        store.remove(id: nap.id)
        XCTAssertTrue(PlanReminderStore(defaults: defaults).all().isEmpty)
    }
}
