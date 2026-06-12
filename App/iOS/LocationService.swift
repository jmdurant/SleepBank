//
//  LocationService.swift
//  SleepBank
//
//  A one-shot, coarse location lookup — just enough to compute the local sunrise/
//  sunset (via SleepBankCore's `Solar`) so the app can tell daytime light from
//  after-dark. City-level accuracy is plenty; the coordinate is cached so sunset is
//  available immediately on the next launch, and everything degrades gracefully when
//  permission is absent.
//

import Foundation
import CoreLocation
import SleepBankCore

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()

    /// Current authorization (for the permissions priming screen).
    var authStatus: CLAuthorizationStatus { manager.authorizationStatus }
    var isAuthorized: Bool {
        authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Cached coordinate (lat, lon), or nil if we've never gotten one.
    var coordinate: (latitude: Double, longitude: Double)? {
        let lat = UserDefaults.standard.double(forKey: "locLat")
        let lon = UserDefaults.standard.double(forKey: "locLon")
        return (lat != 0 || lon != 0) ? (lat, lon) : nil
    }

    /// Today's local sunset (and sunrise), if we have a coordinate.
    func solarToday(_ now: Date = Date()) -> (sunrise: Date, sunset: Date)? {
        guard let c = coordinate else { return nil }
        return Solar.sunriseSunset(date: now, latitude: c.latitude, longitude: c.longitude)
    }

    /// Ask permission (once) and grab a fresh fix. Safe to call on every launch.
    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways {
            m.requestLocation()
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        UserDefaults.standard.set(c.latitude, forKey: "locLat")
        UserDefaults.standard.set(c.longitude, forKey: "locLon")
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { }
}
