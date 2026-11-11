import AppIntents
import Foundation
import NetKit

/// Every value the "Get network value" action can read: the local ones
/// (`NetworkValue`, shared with the widgets) and the three that need a request
/// to the internet. A literal list, because Shortcuts reads it at build time.
enum NetworkQuery: String, AppEnum, CaseIterable {
    case connection, interface, localIPv4, subnetMask, localIPv6, gateway, gatewayIPv6, dnsServers
    case wifiName, bssid, wifiSecurity, vpn, vpnInterface, vpnAddress, cellular, mtu, lowDataMode
    case publicIPv4, publicIPv6, provider

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Network value"

    static let caseDisplayRepresentations: [NetworkQuery: DisplayRepresentation] = [
        .connection: DisplayRepresentation(title: "Connection", image: .init(systemName: "network")),
        .interface: DisplayRepresentation(title: "Active interface", image: .init(systemName: "cable.connector")),
        .localIPv4: DisplayRepresentation(title: "IP address", image: .init(systemName: "number")),
        .subnetMask: DisplayRepresentation(title: "Subnet mask", image: .init(systemName: "square.grid.3x3")),
        .localIPv6: DisplayRepresentation(title: "IPv6 address", image: .init(systemName: "number")),
        .gateway: DisplayRepresentation(title: "Default gateway", image: .init(systemName: "arrow.triangle.branch")),
        .gatewayIPv6: DisplayRepresentation(title: "IPv6 gateway", image: .init(systemName: "arrow.triangle.branch")),
        .dnsServers: DisplayRepresentation(title: "DNS servers", image: .init(systemName: "server.rack")),
        .wifiName: DisplayRepresentation(title: "Wi-Fi name", image: .init(systemName: "wifi")),
        .bssid: DisplayRepresentation(title: "BSSID", image: .init(systemName: "wifi.router")),
        .wifiSecurity: DisplayRepresentation(title: "Wi-Fi security", image: .init(systemName: "lock")),
        .vpn: DisplayRepresentation(title: "VPN status", image: .init(systemName: "lock.shield")),
        .vpnInterface: DisplayRepresentation(title: "VPN interface", image: .init(systemName: "lock.shield")),
        .vpnAddress: DisplayRepresentation(title: "VPN address", image: .init(systemName: "lock.shield")),
        .cellular: DisplayRepresentation(
            title: "Cellular technology", image: .init(systemName: "antenna.radiowaves.left.and.right")),
        .mtu: DisplayRepresentation(title: "Interface MTU", image: .init(systemName: "ruler")),
        .lowDataMode: DisplayRepresentation(title: "Low Data Mode", image: .init(systemName: "tortoise")),
        .publicIPv4: DisplayRepresentation(title: "Public IPv4 address", image: .init(systemName: "globe")),
        .publicIPv6: DisplayRepresentation(title: "Public IPv6 address", image: .init(systemName: "globe")),
        .provider: DisplayRepresentation(title: "Provider", image: .init(systemName: "building.2")),
    ]

    var title: String {
        String(localized: Self.caseDisplayRepresentations[self]?.title ?? "\(rawValue)")
    }

    /// The local value behind this case, `nil` for the external ones.
    var local: NetworkValue? { NetworkValue(rawValue: rawValue) }
}

struct GetNetworkValueIntent: AppIntent {
    static let title: LocalizedStringResource = "Get network value"
    static let description = IntentDescription(
        "Reads one value of the network right now, such as the IP address, the Wi-Fi name or the DNS servers. The public address and the provider are only asked for when external requests are on in Pingscape. Several items come one per line.")
    static let openAppWhenRun = false
    // Siri answers on the Lock Screen too. Addresses and network names only after unlocking.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Value", requestValueDialog: "Which value?")
    var value: NetworkQuery

    static var parameterSummary: some ParameterSummary { Summary("Get \(\.$value)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let (values, sensitive) = try await read()
        let spoken = values.map { IntentSupport.shown($0, sensitive: sensitive) }.joined(separator: ", ")
        return .result(
            value: values.joined(separator: "\n"),
            dialog: IntentSupport.dialog("\(value.title): \(spoken)"))
    }

    @MainActor
    private func read() async throws -> (values: [String], sensitive: Bool) {
        if let local = value.local {
            switch local.read(from: await IntentSupport.snapshot()) {
            case .success(let values): return (values, local.isSensitive)
            case .failure(.needsLocation):
                throw IntentMessage(String(localized: "iOS gives Wi-Fi details only with the location permission. Allow it in Pingscape under About."))
            case .failure(.notPresent):
                throw IntentMessage(local.missingText)
            }
        }
        guard IntentSupport.allowsExternalRequests else {
            throw IntentMessage(String(localized: "External requests are off. Turn them on in Pingscape under About."))
        }
        do {
            switch value {
            case .publicIPv6:
                // Without IPv6 the lookup host has no reachable address, which
                // means there is no public IPv6 address, not a failure.
                let found: String?
                do {
                    found = try await PublicIPLookup.fetch(.v6)
                } catch ToolError.cannotResolve, ToolError.noRoute {
                    found = nil
                }
                guard let address = found else {
                    throw IntentMessage(String(localized: "No public IPv6 address right now"))
                }
                return ([address], true)
            case .provider:
                let address: String
                if let v4 = try? await PublicIPLookup.fetch(.v4) {
                    address = v4
                } else if let v6 = try await PublicIPLookup.fetch(.v6) {
                    address = v6
                } else {
                    throw IntentMessage(String(localized: "No public address right now"))
                }
                guard let info = try await RIPEstat.provider(for: address) else {
                    throw IntentMessage(String(localized: "The address is not announced by any provider"))
                }
                return ([[info.asNumber, info.organization].compactMap { $0 }.joined(separator: " · ")], false)
            default:
                guard let address = try await PublicIPLookup.fetch(.v4) else {
                    throw IntentMessage(String(localized: "No public IPv4 address right now"))
                }
                return ([address], true)
            }
        } catch {
            throw IntentMessage(error)
        }
    }
}

/// All local values at once, for "Get details of" in Shortcuts.
struct NetworkDetails: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Network details"

    @Property(title: "Online") var isOnline: Bool?
    @Property(title: "Connection") var connection: String?
    @Property(title: "Active interface") var interface: String?
    @Property(title: "IP address") var ipAddress: String?
    @Property(title: "Subnet mask") var subnetMask: String?
    @Property(title: "IPv6 address") var ipv6Address: String?
    @Property(title: "Default gateway") var gateway: String?
    @Property(title: "IPv6 gateway") var ipv6Gateway: String?
    @Property(title: "DNS servers") var dnsServers: [String]?
    @Property(title: "Wi-Fi name") var wifiName: String?
    @Property(title: "BSSID") var bssid: String?
    @Property(title: "Wi-Fi security") var wifiSecurity: String?
    @Property(title: "VPN active") var isVPNActive: Bool?
    @Property(title: "VPN status") var vpnStatus: String?
    @Property(title: "VPN interface") var vpnInterfaces: [String]?
    @Property(title: "VPN address") var vpnAddresses: [String]?
    @Property(title: "Cellular technology") var cellular: String?
    @Property(title: "Interface MTU") var mtu: Int?
    @Property(title: "Low Data Mode") var isLowDataMode: Bool?
    @Property(title: "Read at") var readAt: Date?

    init() {}

    init(_ snapshot: NetworkSnapshot) {
        func one(_ value: NetworkValue) -> String? { try? value.read(from: snapshot).get().first }
        func all(_ value: NetworkValue) -> [String]? { try? value.read(from: snapshot).get() }
        isOnline = snapshot.isOnline
        connection = one(.connection)
        interface = one(.interface)
        ipAddress = one(.localIPv4)
        subnetMask = one(.subnetMask)
        ipv6Address = one(.localIPv6)
        gateway = one(.gateway)
        ipv6Gateway = one(.gatewayIPv6)
        dnsServers = all(.dnsServers)
        wifiName = one(.wifiName)
        bssid = one(.bssid)
        wifiSecurity = one(.wifiSecurity)
        isVPNActive = snapshot.isVPNActive
        vpnStatus = one(.vpn)
        vpnInterfaces = all(.vpnInterface)
        vpnAddresses = all(.vpnAddress)
        cellular = one(.cellular)
        mtu = snapshot.primaryInterface?.mtu
        isLowDataMode = snapshot.path?.isConstrained
        readAt = snapshot.takenAt
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(connection ?? String(localized: "Offline"))",
            subtitle: "\(readAt?.formatted(date: .omitted, time: .shortened) ?? "")")
    }
}

struct GetNetworkDetailsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get network details"
    static let description = IntentDescription(
        "Reads all local values of the network at once: connection, addresses, gateway, DNS, Wi-Fi, VPN and cellular. Use \"Get details of\" to pick one. Values the device does not have right now stay empty.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NetworkDetails> {
        .result(value: NetworkDetails(await IntentSupport.snapshot()))
    }
}
