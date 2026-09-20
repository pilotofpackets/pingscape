public enum WiFiSecurity: String, Sendable, Codable, Hashable {
    case open
    case wep
    /// WPA, WPA2 or WPA3 personal. iOS reports only the class, not the version.
    case personal
    case enterprise
    case unknown
}

public struct WiFiInfo: Sendable, Hashable, Codable {
    public let ssid: String
    /// Colon separated, upper case, two digits per byte.
    public let bssid: String?
    public let security: WiFiSecurity
    public let didAutoJoin: Bool?
    public let didJustJoin: Bool?

    public init(
        ssid: String,
        bssid: String? = nil,
        security: WiFiSecurity = .unknown,
        didAutoJoin: Bool? = nil,
        didJustJoin: Bool? = nil
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.security = security
        self.didAutoJoin = didAutoJoin
        self.didJustJoin = didJustJoin
    }
}

public enum RadioTechnology: String, Sendable, Codable, Hashable {
    case gprs
    case edge
    case cdma
    case threeG
    case threeGEVDO
    case lte
    case nrNonStandalone
    case nr
    case unknown

    /// Maps the raw `CTRadioAccessTechnology…` constant.
    public init(coreTelephonyValue raw: String) {
        switch raw {
        case "CTRadioAccessTechnologyNRNSA": self = .nrNonStandalone
        case "CTRadioAccessTechnologyNR": self = .nr
        case "CTRadioAccessTechnologyLTE": self = .lte
        case "CTRadioAccessTechnologyWCDMA", "CTRadioAccessTechnologyHSDPA", "CTRadioAccessTechnologyHSUPA":
            self = .threeG
        case "CTRadioAccessTechnologyeHRPD", "CTRadioAccessTechnologyCDMAEVDORev0",
            "CTRadioAccessTechnologyCDMAEVDORevA", "CTRadioAccessTechnologyCDMAEVDORevB":
            self = .threeGEVDO
        case "CTRadioAccessTechnologyEdge": self = .edge
        case "CTRadioAccessTechnologyGPRS": self = .gprs
        case "CTRadioAccessTechnologyCDMA1x": self = .cdma
        default: self = .unknown
        }
    }

    /// Short label such as "5G NSA". Technical names are not localized.
    public var label: String {
        switch self {
        case .gprs: "2G (GPRS)"
        case .edge: "2G (EDGE)"
        case .cdma: "2G (CDMA)"
        case .threeG: "3G"
        case .threeGEVDO: "3G (EVDO)"
        case .lte: "4G (LTE)"
        case .nrNonStandalone: "5G NSA"
        case .nr: "5G"
        case .unknown: "?"
        }
    }
}

/// One active cellular plan (a SIM or eSIM with a plan).
public struct CellularService: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let isDataService: Bool
    public let technology: RadioTechnology

    public init(id: String, isDataService: Bool, technology: RadioTechnology) {
        self.id = id
        self.isDataService = isDataService
        self.technology = technology
    }
}
