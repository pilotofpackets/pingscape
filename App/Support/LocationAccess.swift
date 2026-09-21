import CoreLocation
import Foundation
import Observation

/// The location permission is only needed to read the Wi-Fi name. The
/// location itself is never requested or used.
enum LocationAccess {
    enum State {
        case notDetermined
        /// The user said no, or a profile forbids it. Only Settings can change that.
        case denied
        case authorized
    }

    static var state: State {
        switch CLLocationManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        case .denied, .restricted: .denied
        default: .notDetermined
        }
    }

    static var isAuthorized: Bool { state == .authorized }
}

@MainActor
@Observable
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private(set) var state = LocationAccess.state
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Asks once. After a refusal the system shows no dialog again, so the
    /// caller offers "Open Settings" instead (see `state`).
    func request() {
        manager.requestWhenInUseAuthorization()
    }

    /// Reads the state again, for example after the user came back from Settings.
    func refresh() {
        state = LocationAccess.state
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.state = LocationAccess.state
            self.onChange?()
        }
    }
}
