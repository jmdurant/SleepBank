import Foundation

/// Sunrise/sunset for a location/date via the standard (NOAA) sunrise equation.
/// Returns absolute UTC `Date`s; `nil` during polar day/night. Pure + testable.
public enum Solar {
    public static func sunriseSunset(date: Date, latitude: Double, longitude: Double)
        -> (sunrise: Date, sunset: Date)? {
        let rad = Double.pi / 180
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = (jd - 2451545.0 + 0.0008).rounded()
        let jStar = n - longitude / 360.0
        let m = (357.5291 + 0.98560028 * jStar).truncatingRemainder(dividingBy: 360)
        let mr = m * rad
        let c = 1.9148 * sin(mr) + 0.0200 * sin(2 * mr) + 0.0003 * sin(3 * mr)
        let lambda = (m + c + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let lr = lambda * rad
        let jTransit = 2451545.0 + jStar + 0.0053 * sin(mr) - 0.0069 * sin(2 * lr)
        let delta = asin(sin(lr) * sin(23.4397 * rad))
        let latR = latitude * rad
        let cosOmega = (sin(-0.833 * rad) - sin(latR) * sin(delta)) / (cos(latR) * cos(delta))
        guard cosOmega >= -1, cosOmega <= 1 else { return nil }   // polar day/night
        let omega = acos(cosOmega) / rad
        func julianToDate(_ j: Double) -> Date { Date(timeIntervalSince1970: (j - 2440587.5) * 86400) }
        return (julianToDate(jTransit - omega / 360.0), julianToDate(jTransit + omega / 360.0))
    }
}

/// The circadian color-temperature curve — what daylight-sync plugins do: warm at
/// the horizon, coolest at solar noon, on a cosine curve (`exponent` steepens it).
/// Location-aware via `Solar`; degrades to a rhythm-anchored curve without coordinates.
public enum CircadianLighting {

    /// Kelvin for `now`, given the day's sunrise/sunset and warm/cool bounds.
    public static func kelvin(at now: Date, sunrise: Date, sunset: Date,
                              warmK: Int = 2700, coolK: Int = 5000, exponent: Double = 3) -> Int {
        guard sunset > sunrise else { return warmK }
        guard now > sunrise, now < sunset else { return warmK }   // night → warm
        let frac = now.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)   // 0…1
        let intensity = pow(sin(Double.pi * frac), exponent)       // 0 at edges, 1 at noon
        return Int((Double(warmK) + (Double(coolK) - Double(warmK)) * intensity).rounded())
    }

    /// Convenience: Kelvin from coordinates (falls back to warm during polar night).
    public static func kelvin(at now: Date, latitude: Double, longitude: Double,
                              warmK: Int = 2700, coolK: Int = 5000, exponent: Double = 3) -> Int {
        guard let s = Solar.sunriseSunset(date: now, latitude: latitude, longitude: longitude) else { return warmK }
        return kelvin(at: now, sunrise: s.sunrise, sunset: s.sunset, warmK: warmK, coolK: coolK, exponent: exponent)
    }

    /// Rhythm-anchored fallback when there's no location: cool early after wake,
    /// neutral midday, warm after wind-down (wake + ~15.5 h). Circular over 24 h.
    public static func kelvinFromRhythm(at now: Date, wakeTime: Date,
                                        warmK: Int = 2700, coolK: Int = 5000,
                                        calendar: Calendar = .current) -> Int {
        func mins(_ d: Date) -> Int { calendar.component(.hour, from: d) * 60 + calendar.component(.minute, from: d) }
        let sinceWake = (((mins(now) - mins(wakeTime)) % 1440) + 1440) % 1440
        let awake = Int(15.5 * 60)
        if sinceWake >= awake { return warmK }                    // wind-down → warm
        if sinceWake < 180 { return (warmK + coolK) / 2 }          // first 3 h: mid
        return coolK                                              // day: cool
    }

    public static func kelvinToMireds(_ k: Int) -> Int { Int((1_000_000.0 / Double(max(k, 1))).rounded()) }
}
