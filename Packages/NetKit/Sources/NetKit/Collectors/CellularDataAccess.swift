#if os(iOS)
import CoreTelephony
#endif

/// Whether the user allowed mobile data for this app (Settings → Cellular).
public enum CellularDataAccess: Sendable, Equatable {
    case allowed
    case restricted
    /// The system did not say (yet). The row is left out.
    case unknown

    #if os(iOS)
    private final class Monitor: @unchecked Sendable {
        // The state arrives asynchronously after the object is created, so one
        // instance is kept for the life of the app.
        let data = CTCellularData()
    }

    private static let monitor = Monitor()

    public static var current: CellularDataAccess {
        switch monitor.data.restrictedState {
        case .notRestricted: .allowed
        case .restricted: .restricted
        default: .unknown
        }
    }
    #else
    public static var current: CellularDataAccess { .unknown }
    #endif
}
