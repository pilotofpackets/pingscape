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
                    InfoSection(title: service.title(in: snapshot.cellularServices)) {
                        DataRow(label: "Radio technology", value: service.technology.label)
                        if snapshot.cellularServices.count > 1 {
                            DataRow(
                                label: "Mobile data",
                                value: String(localized: service.isDataService ? "Yes" : "No"))
                        }
                    }
                }
                if let data = snapshot.interface(of: .cellular) {
                    InfoSection(title: "Data connection") {
                        RowList(rows: Rows.addresses(of: data))
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
    /// "First SIM" and "Second SIM" by slot, "SIM 3" … beyond that, and just
    /// "SIM" when there is one. Which one carries mobile data is said next to
    /// it (`statusText`), not in the name: named "Data SIM" and sorted first,
    /// the rows swapped places when the user switched data to the other SIM.
    func title(in services: [CellularService]) -> LocalizedStringResource {
        guard services.count > 1, let index = services.firstIndex(of: self) else { return "SIM" }
        switch index {
        case 0: return "First SIM"
        case 1: return "Second SIM"
        default: return "SIM \(index + 1)"
        }
    }

    /// The radio technology, and for the SIM that carries mobile data a note
    /// saying so (only when there is more than one SIM).
    func statusText(among services: [CellularService]) -> String {
        guard isDataService, services.count > 1 else { return technology.label }
        return technology.label + " · " + String(localized: "Mobile data")
    }
}
