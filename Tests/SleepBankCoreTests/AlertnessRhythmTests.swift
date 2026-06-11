import XCTest
@testable import SleepBankCore

final class AlertnessRhythmTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// A date at a given clock hour on a fixed reference day (UTC).
    private func at(_ hour: Double) -> Date {
        let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return base.addingTimeInterval(hour * 3600)
    }

    private func rhythm(debt: Double, naps: [AlertnessRhythm.Nap] = []) -> AlertnessRhythm {
        AlertnessRhythm(wakeTime: at(7), sleepDebt: debt, naps: naps, calendar: cal)
    }

    // MARK: - Chronotype phase shift

    func testPhaseShiftZeroForAverageSleeper() {
        // 11pm–7am → midpoint 3:00am = the reference → no shift.
        XCTAssertEqual(AlertnessRhythm.phaseShift(bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60),
                       0, accuracy: 0.01)
    }

    func testPhaseShiftLaterForOwl() {
        // 2am–10am → midpoint 6:00am → ~3 h later (clamped at 4).
        let shift = AlertnessRhythm.phaseShift(bedtimeMinutes: 2 * 60, wakeMinutes: 10 * 60)
        XCTAssertEqual(shift, 3, accuracy: 0.01)
    }

    func testPhaseShiftEarlierForLark() {
        // 9:30pm–5:30am → midpoint 1:30am → ~1.5 h earlier.
        let shift = AlertnessRhythm.phaseShift(bedtimeMinutes: 21 * 60 + 30, wakeMinutes: 5 * 60 + 30)
        XCTAssertEqual(shift, -1.5, accuracy: 0.01)
    }

    func testShiftSlidesTheCurveLater() {
        // An owl's curve at a given clock hour equals the un-shifted curve `shift`
        // hours earlier — i.e. the whole shape moves later by `shift`.
        let base = AlertnessRhythm(wakeTime: at(7), sleepDebt: 0.2, calendar: cal)
        let owl = AlertnessRhythm(wakeTime: at(7), sleepDebt: 0.2, circadianShiftHours: 2, calendar: cal)
        // The afternoon dip sits ~2 h later for the owl, so at 3:30pm the owl is still
        // higher than the un-shifted curve (whose dip is right then).
        XCTAssertGreaterThan(owl.level(at: at(15.5)), base.level(at: at(15.5)))
    }

    func testLevelsStayInUnitRange() {
        let r = rhythm(debt: 0.3)
        for h in stride(from: 7.0, through: 23.0, by: 0.5) {
            let v = r.level(at: at(h))
            XCTAssert(v >= 0 && v <= 1, "level \(v) out of range at \(h)h")
        }
    }

    func testLessOvernightSleepLowersTheWholeCurve() {
        let rested = rhythm(debt: 0.06)
        let tired = rhythm(debt: 0.45)
        for h in stride(from: 8.0, through: 22.0, by: 1.0) {
            XCTAssertLessThan(tired.level(at: at(h)), rested.level(at: at(h)),
                              "a short night should sit lower at \(h)h")
        }
    }

    func testAfternoonDipIsBelowTheEveningWakeMaintenanceZone() {
        let r = rhythm(debt: 0.1)
        // ~15:30 post-lunch dip should be below the ~19:00 second wind.
        XCTAssertLessThan(r.level(at: at(15.5)), r.level(at: at(19.0)))
        // …and below late morning, i.e. a genuine dip.
        XCTAssertLessThan(r.level(at: at(15.5)), r.level(at: at(12.0)))
    }

    func testNightIsLowerThanMidday() {
        let r = rhythm(debt: 0.1)
        XCTAssertLessThan(r.level(at: at(4.0)), r.level(at: at(12.0)))
    }

    func testNapLiftsAlertnessThenRejoinsBaseline() {
        let r = rhythm(debt: 0.3)
        let napAt = at(14.0)
        // Shortly after a nap, projected alertness exceeds the baseline.
        let soon = at(14.75)
        XCTAssertGreaterThan(r.level(at: soon, withNapAt: napAt, type: .power),
                             r.level(at: soon))
        // Hours later the lift has faded — the curves rejoin.
        let later = at(20.0)
        XCTAssertEqual(r.level(at: later, withNapAt: napAt, type: .power),
                       r.level(at: later), accuracy: 0.02)
    }

    func testLateNapKeepsTheNightMoreAlertThanAnEarlyNap() {
        // The cost of a late nap: at bedtime, an early-afternoon nap has fully faded,
        // but an evening nap still keeps you elevated — i.e. less sleepy when you want
        // to sleep. Compared at a common 23:00 bedtime.
        let r = rhythm(debt: 0.3)
        let bedtime = at(23.0)
        let earlyNap = r.level(at: bedtime, withNapAt: at(13.0), type: .cycle) - r.level(at: bedtime)
        let lateNap  = r.level(at: bedtime, withNapAt: at(20.0), type: .cycle) - r.level(at: bedtime)
        XCTAssertGreaterThan(lateNap, earlyNap + 0.05)   // markedly worse for the night
        XCTAssertGreaterThan(lateNap, 0.03)              // a late deep nap visibly steals night sleepiness
    }

    func testWorkoutLiftsMoreThanWalkButLessThanNap() {
        let r = rhythm(debt: 0.3)
        let start = at(14.0)
        let soon = at(14.6)   // ~35 min in, near the arousal peak
        let walk = AlertnessRhythm.Activity(intensity: .walk, outdoors: true, start: start, duration: 1800)
        let workout = AlertnessRhythm.Activity(intensity: .workout, outdoors: false, start: start, duration: 3600)
        let walkLift = r.level(at: soon, naps: [], activities: [walk]) - r.level(at: soon)
        let workoutLift = r.level(at: soon, naps: [], activities: [workout]) - r.level(at: soon)
        let napLift = r.level(at: soon, withNapAt: at(14.0), type: .power) - r.level(at: soon)
        XCTAssertGreaterThan(walkLift, 0)
        XCTAssertGreaterThan(workoutLift, walkLift)
        XCTAssertLessThan(workoutLift, napLift)   // exercise arousal stays under a nap
    }

    func testActivityArousalFadesWithinACoupleHours() {
        let r = rhythm(debt: 0.3)
        let start = at(14.0)
        let workout = AlertnessRhythm.Activity(intensity: .workout, outdoors: false, start: start, duration: 3600)
        let soon = r.level(at: at(14.6), naps: [], activities: [workout]) - r.level(at: at(14.6))
        let later = r.level(at: at(17.5), naps: [], activities: [workout]) - r.level(at: at(17.5))
        XCTAssertGreaterThan(soon, later)
        XCTAssertEqual(later, 0, accuracy: 0.02)   // mostly gone ~3.5 h on
    }

    func testNapAndActivityStack() {
        let r = rhythm(debt: 0.3)
        let t = at(15.0)
        let workout = AlertnessRhythm.Activity(intensity: .workout, outdoors: false, start: at(14.5), duration: 3600)
        let napOnly = r.level(at: t, naps: [AlertnessRhythm.Nap(end: at(13.5), type: .power, fullness: 1)], activities: [])
        let napPlus = r.level(at: t, naps: [AlertnessRhythm.Nap(end: at(13.5), type: .power, fullness: 1)], activities: [workout])
        XCTAssertGreaterThan(napPlus, napOnly)
    }

    func testLateDeepNapLeavesYouMoreAlertThanRestedAtBedtime() {
        // The "can't fall asleep" signal: after a late 90-min nap, bedtime alertness
        // sits *above* a fully-rested person's — you're too wired to sleep.
        let tired = rhythm(debt: 0.4)
        let rested = rhythm(debt: 0.05)
        let bedtime = at(23.0)
        let nappedAtBed = tired.level(at: bedtime, withNapAt: at(19.0), type: .cycle)
        XCTAssertGreaterThan(nappedAtBed, rested.level(at: bedtime))
    }

    func testCycleNapLiftsMoreThanPowerNap() {
        let r = rhythm(debt: 0.3)
        let napAt = at(14.0)
        // Measure after both naps have ended (power ~14:18, cycle ~15:30).
        let after = at(16.0)
        let powerLift = r.level(at: after, withNapAt: napAt, type: .power) - r.level(at: after)
        let cycleLift = r.level(at: after, withNapAt: napAt, type: .cycle) - r.level(at: after)
        XCTAssertGreaterThan(cycleLift, powerLift)
    }

    func testCycleNapBenefitOutlastsPowerNap() {
        // The cycle nap's value is durability: hours later it's still clearly lifting
        // you while the power nap has mostly faded.
        let r = rhythm(debt: 0.3)
        let napAt = at(13.0)
        let late = at(18.0)
        let powerLift = r.level(at: late, withNapAt: napAt, type: .power) - r.level(at: late)
        let cycleLift = r.level(at: late, withNapAt: napAt, type: .cycle) - r.level(at: late)
        XCTAssertGreaterThan(cycleLift, powerLift + 0.04)
    }

    func testCycleNapDoesNotPinCurveToTheCeiling() {
        // A deep nap should lift you to ~your rested level, not slam the curve to the
        // top — i.e. it must not over-discharge pressure into the floor.
        let tired = rhythm(debt: 0.45)
        let napAt = at(13.0)
        let peak = at(13.0 + 90.0/60 + 0.75)   // ~the modelled benefit peak
        let napped = tired.level(at: peak, withNapAt: napAt, type: .cycle)
        XCTAssertLessThan(napped, 0.95)   // boosted, but not pinned at the maximum
    }

    func testReadingsSpanTheRequestedWindow() {
        let r = rhythm(debt: 0.2)
        let readings = r.readings(from: at(7), to: at(23), step: 3600)
        XCTAssertEqual(readings.count, 17)              // 7…23 inclusive, hourly
        XCTAssertEqual(readings.first?.date, at(7))
        XCTAssertEqual(readings.last?.date, at(23))
    }

    func testMorningLightLiftsTheMorningThenFadesByMidday() {
        let dim = AlertnessRhythm(wakeTime: at(7), sleepDebt: 0.3, morningLightDose: 0, calendar: cal)
        let bright = AlertnessRhythm(wakeTime: at(7), sleepDebt: 0.3, morningLightDose: 1, calendar: cal)
        // Morning (~1.5 h after wake): bright sits higher than dim.
        XCTAssertGreaterThan(bright.level(at: at(8.5)), dim.level(at: at(8.5)))
        // By mid-afternoon the lift has faded — curves converge.
        XCTAssertEqual(bright.level(at: at(15.0)), dim.level(at: at(15.0)), accuracy: 0.01)
    }

    func testMorningLightBoostIsSmall() {
        let dim = AlertnessRhythm(wakeTime: at(7), sleepDebt: 0.3, morningLightDose: 0, calendar: cal)
        let bright = AlertnessRhythm(wakeTime: at(7), sleepDebt: 0.3, morningLightDose: 1, calendar: cal)
        // A full morning-light dose is a modest nudge (< 0.1 on the 0…1 curve),
        // deliberately smaller than a nap — the evidence is for anchoring, not a jolt.
        let lift = bright.level(at: at(8.5)) - dim.level(at: at(8.5))
        XCTAssertGreaterThan(lift, 0.01)
        XCTAssertLessThan(lift, 0.1)
    }

    func testMorningLightDoseSaturates() {
        XCTAssertEqual(AlertnessRhythm.morningLightDose(minutes: 0), 0, accuracy: 0.001)
        XCTAssertEqual(AlertnessRhythm.morningLightDose(minutes: 10, target: 20), 0.5, accuracy: 0.001)
        XCTAssertEqual(AlertnessRhythm.morningLightDose(minutes: 40, target: 20), 1.0, accuracy: 0.001)  // capped
    }

    func testMorningActivityAddsItsOwnLiftOnTopOfLight() {
        let lightOnly = AlertnessRhythm(wakeTime: at(7), sleepDebt: 0.3, morningLightDose: 1, calendar: cal)
        let lightAndWalk = AlertnessRhythm(wakeTime: at(7), sleepDebt: 0.3,
                                           morningLightDose: 1, morningActivityDose: 1, calendar: cal)
        // A morning walk earns extra credit on top of light…
        XCTAssertGreaterThan(lightAndWalk.level(at: at(8.5)), lightOnly.level(at: at(8.5)))
        // …but the combined morning lift is still capped (stays modest, < 0.12 display).
        let dim = AlertnessRhythm(wakeTime: at(7), sleepDebt: 0.3, calendar: cal)
        XCTAssertLessThan(lightAndWalk.level(at: at(8.5)) - dim.level(at: at(8.5)), 0.12)
    }

    func testMorningActivityDoseSaturates() {
        XCTAssertEqual(AlertnessRhythm.morningActivityDose(minutes: 0), 0, accuracy: 0.001)
        XCTAssertEqual(AlertnessRhythm.morningActivityDose(minutes: 30, target: 15), 1.0, accuracy: 0.001)
    }

    func testShortNightFlagFromSleep() {
        let short = AlertnessRhythm.fromSleep(wakeTime: at(6), sleptHours: 5.0,
                                              typicalHours: 7.5, now: at(9), calendar: cal)
        XCTAssertTrue(short.isShortNight)
        let fine = AlertnessRhythm.fromSleep(wakeTime: at(6), sleptHours: 7.5,
                                             typicalHours: 7.5, now: at(9), calendar: cal)
        XCTAssertFalse(fine.isShortNight)
        // A short night carries more start-of-day pressure.
        XCTAssertGreaterThan(short.sleepDebt, fine.sleepDebt)
    }
}
