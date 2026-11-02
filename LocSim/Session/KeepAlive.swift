import CoreLocation
import Foundation

/// Runs coarse location updates so iOS keeps the app (and the DVT channel) alive
/// in the background. The fixes themselves are ignored.
final class KeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var session: CLBackgroundActivitySession?
    private(set) var isRunning = false

    var onStatus: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        // Stop updates the system may have resumed from a previous run.
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            onStatus?("Location permission denied, background keep-alive off")
        default:
            begin()
        }
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        session?.invalidate()
        session = nil
        onStatus?("keep-alive off")
    }

    private func begin() {
        manager.allowsBackgroundLocationUpdates = true
        session = session ?? CLBackgroundActivitySession()
        manager.startUpdatingLocation()
        onStatus?("keep-alive on")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRunning else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            begin()
        case .denied, .restricted:
            onStatus?("Location permission denied, background keep-alive off")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
