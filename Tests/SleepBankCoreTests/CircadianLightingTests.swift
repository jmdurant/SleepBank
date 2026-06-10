import XCTest
@testable import SleepBankCore

final class CircadianLightingTests: XCTestCase {

    // London, near the March 2024 equinox — day ≈ night, sunrise/sunset ≈ 06/18 UTC.
    private let londonLat = 51.5074, londonLon = -0.1278
    private var equinox: Date { Date(timeIntervalSince1970: 1_710_892_800) } // 2024-03-20 00:00 UTC

    func testSunriseSunsetIsSaneAtEquinox() {
        guard let s = Solar.sunriseSunset(date: equinox, latitude: londonLat, longitude: londonLon) else {
            return XCTFail("expected sunrise/sunset")
        }
        XCTAssertLessThan(s.sunrise, s.sunset)
        let dayHours = s.sunset.timeIntervalSince(s.sunrise) / 3600
        XCTAssertEqual(dayHours, 12, accuracy: 1.5)   // ~12 h at equinox

        let cal = Calendar(identifier: .gregorian)
        var utc = cal; utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Double(utc.component(.hour, from: s.sunrise)), 6, accuracy: 1.5)
        XCTAssertEqual(Double(utc.component(.hour, from: s.sunset)), 18, accuracy: 1.5)
    }

    func testPolarNightReturnsWarm() {
        // High Arctic in deep winter → no sunrise → warm fallback.
        let midwinter = Date(timeIntervalSince1970: 1_703_462_400)  // 2023-12-25
        XCTAssertNil(Solar.sunriseSunset(date: midwinter, latitude: 80, longitude: 0))
        XCTAssertEqual(CircadianLighting.kelvin(at: midwinter, latitude: 80, longitude: 0, warmK: 2700, coolK: 5000), 2700)
    }

    func testCoolestAtSolarNoonWarmAtEdges() {
        let sunrise = Date(timeIntervalSince1970: 1_710_910_800)         // arbitrary
        let sunset = sunrise.addingTimeInterval(12 * 3600)
        let noon = sunrise.addingTimeInterval(6 * 3600)
        XCTAssertEqual(CircadianLighting.kelvin(at: noon, sunrise: sunrise, sunset: sunset, warmK: 2700, coolK: 5000), 5000)
        XCTAssertEqual(CircadianLighting.kelvin(at: sunrise, sunrise: sunrise, sunset: sunset, warmK: 2700, coolK: 5000), 2700)
        // Night → warm.
        XCTAssertEqual(CircadianLighting.kelvin(at: sunrise.addingTimeInterval(-3600), sunrise: sunrise, sunset: sunset, warmK: 2700, coolK: 5000), 2700)
    }

    func testMiddayIsBetweenWarmAndCool() {
        let sunrise = Date(timeIntervalSince1970: 1_710_910_800)
        let sunset = sunrise.addingTimeInterval(12 * 3600)
        let midMorning = sunrise.addingTimeInterval(3 * 3600)
        let k = CircadianLighting.kelvin(at: midMorning, sunrise: sunrise, sunset: sunset, warmK: 2700, coolK: 5000)
        XCTAssertGreaterThan(k, 2700)
        XCTAssertLessThan(k, 5000)
    }

    func testKelvinToMireds() {
        XCTAssertEqual(CircadianLighting.kelvinToMireds(2700), 370, accuracy: 2)
        XCTAssertEqual(CircadianLighting.kelvinToMireds(5000), 200, accuracy: 2)
    }

    func testRhythmFallbackWarmAfterWindDown() {
        let cal = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
        let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_710_892_800))
        let wake = base.addingTimeInterval(7 * 3600)             // 07:00
        let morning = base.addingTimeInterval(8 * 3600)          // 08:00 → cool-ish
        let lateEvening = base.addingTimeInterval(23 * 3600)     // 23:00 → past wind-down → warm
        XCTAssertEqual(CircadianLighting.kelvinFromRhythm(at: lateEvening, wakeTime: wake, warmK: 2700, coolK: 5000, calendar: cal), 2700)
        XCTAssertGreaterThan(CircadianLighting.kelvinFromRhythm(at: morning, wakeTime: wake, warmK: 2700, coolK: 5000, calendar: cal), 2700)
    }
}
