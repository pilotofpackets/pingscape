import CoreLocation
import Foundation

/// The location permission is only needed to read the Wi-Fi name. The
/// location itself is never requested or used.
enum LocationAccess {
    static var isAuthorized: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
}

@MainActor
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    var onChange: (() -> Void)?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.onChange?() }
    }
}
