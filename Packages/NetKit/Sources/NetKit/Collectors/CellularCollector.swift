#if os(iOS)
import CoreTelephony
import Foundation

/// Reads the active cellular plans and their radio technology.
///
/// No permission is needed. The carrier name is not readable on current iOS
/// versions and is not part of the model.
public enum CellularCollector {
    /// Posted when the user switches mobile data to another SIM. The radio
    /// technology has its own system notification
    /// (`CTServiceRadioAccessTechnologyDidChange`); this one has none.
    public static let dataServiceDidChange = Notification.Name("app.pingscape.cellular.dataServiceDidChange")

    /// One instance kept for the whole run, only so that the system posts
    /// `CTServiceRadioAccessTechnologyDidChange` and calls the delegate when
    /// mobile data moves to the other SIM: without a live instance neither
    /// happens. Its own values are not read. Measured on an iPhone 15
    /// (2026-11-01): after a switch from LTE back to 5G it kept reporting
    /// LTE, with no notification, while a new instance read at the same
    /// moment reported 5G NSA.
    nonisolated(unsafe) private static let info: CTTelephonyNetworkInfo = {
        let info = CTTelephonyNetworkInfo()
        info.delegate = dataService
        return info
    }()

    /// Creates the long-lived instance on the main thread, where the system
    /// delivers its notification and delegate calls.
    @MainActor public static func start() {
        _ = info
    }

    /// The SIM used for data, as the delegate last reported it. The
    /// long-lived instance's own `dataServiceIdentifier` kept the old SIM
    /// after mobile data was switched to the other one with the app open
    /// (found 2026-11-01); the delegate call names the new one.
    private static let dataService = DataServiceTracker()

    public static func services() -> [CellularService] {
        // A new instance per read for the values (see `info`).
        let current = CTTelephonyNetworkInfo()
        let technologies = current.serviceCurrentRadioAccessTechnology ?? [:]
        let dataServiceID = dataService.identifier ?? current.dataServiceIdentifier
        return technologies
            .map { id, raw in
                CellularService(
                    id: id,
                    isDataService: id == dataServiceID,
                    technology: RadioTechnology(coreTelephonyValue: raw))
            }
            // A fixed order (the SIM slots), so switching mobile data to the
            // other SIM does not swap the rows.
            .sorted { $0.id < $1.id }
    }

    private final class DataServiceTracker: NSObject, CTTelephonyNetworkInfoDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var latest: String?

        var identifier: String? {
            lock.lock()
            defer { lock.unlock() }
            return latest
        }

        func dataServiceIdentifierDidChange(_ identifier: String) {
            lock.lock()
            latest = identifier
            lock.unlock()
            NotificationCenter.default.post(name: CellularCollector.dataServiceDidChange, object: nil)
        }
    }
}
#endif
