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

    /// One instance for the whole run. CoreTelephony keeps the radio state
    /// current, and posts `CTServiceRadioAccessTechnologyDidChange`, only
    /// while an instance is alive. A new one per read gave a stale answer
    /// (4G after switching on Airplane Mode, found 2026-11-01) and never a
    /// change notification.
    nonisolated(unsafe) private static let info: CTTelephonyNetworkInfo = {
        let info = CTTelephonyNetworkInfo()
        info.delegate = dataService
        return info
    }()

    /// The SIM used for data, as the delegate last reported it. The
    /// instance's own `dataServiceIdentifier` kept the old SIM after mobile
    /// data was switched to the other one with the app open (found
    /// 2026-11-01); the delegate call names the new one.
    private static let dataService = DataServiceTracker()

    public static func services() -> [CellularService] {
        let technologies = info.serviceCurrentRadioAccessTechnology ?? [:]
        let dataServiceID = dataService.identifier ?? info.dataServiceIdentifier
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
