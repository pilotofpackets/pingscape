#if os(iOS)
import CoreTelephony

/// Reads the active cellular plans and their radio technology.
///
/// No permission is needed. The carrier name is not readable on current iOS
/// versions and is not part of the model.
public enum CellularCollector {
    /// One instance for the whole run. CoreTelephony keeps the radio state
    /// current, and posts `CTServiceRadioAccessTechnologyDidChange`, only
    /// while an instance is alive. A new one per read gave a stale answer
    /// (4G after switching on Airplane Mode, found 2026-11-01) and never a
    /// change notification.
    nonisolated(unsafe) private static let info = CTTelephonyNetworkInfo()

    public static func services() -> [CellularService] {
        let technologies = info.serviceCurrentRadioAccessTechnology ?? [:]
        let dataServiceID = info.dataServiceIdentifier
        return technologies
            .map { id, raw in
                CellularService(
                    id: id,
                    isDataService: id == dataServiceID,
                    technology: RadioTechnology(coreTelephonyValue: raw))
            }
            .sorted { lhs, rhs in
                if lhs.isDataService != rhs.isDataService { return lhs.isDataService }
                return lhs.id < rhs.id
            }
    }
}
#endif
