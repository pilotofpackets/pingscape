#if os(iOS)
import CoreTelephony

/// Reads the active cellular plans and their radio technology.
///
/// No permission is needed. The carrier name is not readable on current iOS
/// versions and is not part of the model.
public enum CellularCollector {
    public static func services() -> [CellularService] {
        let info = CTTelephonyNetworkInfo()
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
