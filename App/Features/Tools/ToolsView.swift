import NetKit
import SwiftUI

extension ToolKind {
    var title: LocalizedStringResource {
        switch self {
        case .ping: "Ping"
        case .traceroute: "Traceroute"
        case .dns: "DNS"
        case .whois: "Whois"
        case .ports: "Ports"
        case .tls: "TLS"
        case .http: "HTTP"
        case .subnet: "Subnet"
        case .oui: "OUI"
        }
    }
}

struct ToolsView: View {
    @Environment(SnapshotStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(PrivacyMask.self) private var mask
    @State private var selected: ToolKind
    @State private var history = ToolHistory()
    @State private var sections: [SectionRecord] = []
    @State private var ping: PingModel
    @State private var traceroute: TracerouteModel
    @State private var dns: DNSModel
    @State private var whois: WhoisModel
    @State private var ports: PortsModel
    @State private var tls: TLSModel
    @State private var http: HTTPModel
    @State private var subnetInput = ""
    @State private var ouiInput = ""

    init() {
        let demo = DemoLaunch.tool != nil
        _selected = State(initialValue: DemoLaunch.tool ?? .ping)
        _ping = State(initialValue: demo ? .demo() : PingModel())
        _traceroute = State(initialValue: demo ? .demo() : TracerouteModel())
        _dns = State(initialValue: demo ? .demo() : DNSModel())
        _whois = State(initialValue: demo ? .demo() : WhoisModel())
        _ports = State(initialValue: demo ? .demo() : PortsModel())
        _tls = State(initialValue: demo ? .demo() : TLSModel())
        _http = State(initialValue: demo ? .demo() : HTTPModel())
        _subnetInput = State(initialValue: demo ? "192.168.178.42/24" : "")
        _ouiInput = State(initialValue: demo ? "3C:A6:2F:1B:D3:22" : "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    chips
                    content
                        .padding(.horizontal, 16)
                }
                .readableContentWidth()
                .padding(.top, 8)
                // Room for the floating button.
                .padding(.bottom, control == nil ? 24 : 88)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                if let control {
                    StartBar(control: control) { history.remember(control.inputText, for: selected) }
                }
            }
            .navigationTitle("Tools")
            .toolbar {
                if !sections.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ResultActions(text: resultText)
                    }
                }
            }
            .onPreferenceChange(SectionRecordsKey.self) { sections = $0 }
            .onChange(of: navigation.toolRequest, initial: true) { _, request in
                if let request { apply(request) }
            }
            .onChange(of: store.snapshot?.takenAt, initial: true) { _, _ in prepare() }
        }
    }

    /// What a copy or share of the result holds: the sections on screen.
    private var resultText: String {
        ReportFormatter.text(header: [], sections: sections.reportSections, masked: mask.isMasked)
    }

    // MARK: Chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ToolKind.allCases) { tool in
                    Button {
                        selected = tool
                    } label: {
                        Text(tool.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selected == tool ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule()
                            )
                            .foregroundStyle(selected == tool ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == tool ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch selected {
        case .ping: PingView(model: ping, history: history)
        case .traceroute: TracerouteView(model: traceroute, history: history)
        case .dns: DNSView(model: dns, history: history)
        case .whois: WhoisView(model: whois, history: history)
        case .ports: PortsView(model: ports, history: history)
        case .tls: TLSView(model: tls, history: history)
        case .http: HTTPView(model: http, history: history)
        case .subnet: SubnetView(input: $subnetInput)
        case .oui: OUIView(input: $ouiInput)
        }
    }

    private var control: (any ToolControl)? {
        switch selected {
        case .ping: ping
        case .traceroute: traceroute
        case .dns: dns
        case .whois: whois
        case .ports: ports
        case .tls: tls
        case .http: http
        case .subnet, .oui: nil
        }
    }

    // MARK: Prefill

    /// A device in the LAN list opens a tool with its address filled in.
    private func apply(_ request: ToolRequest) {
        selected = request.tool
        switch request.tool {
        case .ping: ping.input = request.target
        case .traceroute: traceroute.input = request.target
        case .ports:
            ports.input = request.target
            ports.classify()
        case .dns: dns.input = request.target
        case .whois: whois.input = request.target
        case .tls: tls.input = request.target
        case .http: http.input = request.target
        case .subnet, .oui: break
        }
        navigation.toolRequest = nil
    }

    /// Follows the network: the DNS servers for the DNS tool, the gateway as the
    /// first port target, the own network for the subnet calculator.
    private func prepare() {
        guard let snapshot = store.snapshot, !DemoLaunch.isDemo else { return }
        dns.systemServers = snapshot.dnsServers
        if ports.input.isEmpty, let gateway = snapshot.localGateway4 {
            ports.input = gateway
            ports.classify()
        }
        if subnetInput.isEmpty, let address = snapshot.primaryIPv4, let prefix = address.prefixLength {
            subnetInput = "\(address.ip)/\(prefix)"
        }
    }
}
