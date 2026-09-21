import NetKit
import SwiftUI

struct CellularDetailView: View {
    @Environment(SnapshotStore.self) private var store

    var body: some View {
        let snapshot = store.snapshot
        DetailPage(
            title: "Cellular", isAvailable: snapshot.map { !$0.knownCellularServices.isEmpty } ?? true
        ) {
            if let snapshot {
                let services = snapshot.knownCellularServices
                ForEach(services) { service in
                    InfoSection(title: service.title(among: snapshot.cellularServices.count)) {
                        DataRow(label: "Radio technology", value: service.technology.label)
                    }
                }
                if let data = snapshot.interface(of: .cellular) {
                    InfoSection(title: "Data connection") {
                        Rows.addresses(of: data)
                    }
                    TrafficSection(interface: data)
                }
                switch store.cellularAccess {
                case .allowed:
                    InfoSection(title: "System") {
                        DataRow(label: "Mobile data for Pingscape", value: String(localized: "Allowed"))
                    }
                case .restricted:
                    InfoSection(title: "System") {
                        DataRow(label: "Mobile data for Pingscape", value: String(localized: "Off"))
                    }
                case .unknown:
                    EmptyView()
                }
            }
        }
    }
}

extension NetworkSnapshot {
    /// The plans whose radio technology iOS reported. A plan without one adds
    /// no row.
    var knownCellularServices: [CellularService] {
        cellularServices.filter { $0.technology != .unknown }
    }
}

extension CellularService {
    /// "Data SIM", "Second SIM", or "Other SIM" if there are more than two.
    func title(among total: Int) -> LocalizedStringResource {
        if isDataService { return "Data SIM" }
        return total > 2 ? "Other SIM" : "Second SIM"
    }
}
