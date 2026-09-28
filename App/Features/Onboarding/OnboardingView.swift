import SwiftUI

/// A short guided tour of the five tabs, shown once right after first
/// launch and replayable from About. On the last page it hands back to the
/// caller, which then shows the one question about external requests (see
/// `ExternalPromptSheet` in `RootView`).
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private static let pageCount = 6

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < Self.pageCount - 1 {
                    Button("Skip", action: onFinish)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(height: 20)
            .padding([.horizontal, .top], 16)

            TabView(selection: $page) {
                WelcomePage().tag(0)
                OverviewPage().tag(1)
                LANPage().tag(2)
                LivePage().tag(3)
                ToolsPage().tag(4)
                PrivacyPage().tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < Self.pageCount - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < Self.pageCount - 1 ? "Next" : "Get started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Page shell

/// Icon, title, one paragraph, and a small annotated mockup of the tab it explains.
private struct OnboardingPage<Diagram: View>: View {
    let symbol: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    @ViewBuilder let diagram: Diagram

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                    .padding(.top, 8)
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                diagram
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .readableContentWidth(420)
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        OnboardingPage(
            symbol: "dot.radiowaves.left.and.right", title: "Welcome to Pingscape",
            message:
                "Pingscape shows what is going on with this connection — on this iPhone, in the local network, and on the internet. A short tour of what's here."
        ) {
            HStack(spacing: 18) {
                stop("square.grid.2x2", "Overview")
                stop("network", "LAN")
                stop("waveform.path.ecg", "Live")
                stop("wrench.and.screwdriver", "Tools")
                stop("info.circle", "About")
            }
            .padding(.top, 8)
        }
    }

    private func stop(_ symbol: String, _ title: LocalizedStringResource) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OverviewPage: View {
    var body: some View {
        OnboardingPage(
            symbol: "square.grid.2x2", title: "See the connection at a glance",
            message:
                "Overview shows whether you're online and how — Wi-Fi, cellular or a VPN. Tap Details on any card for everything behind it."
        ) {
            MockCard {
                AnnotatedRow(
                    label: "Status", value: String(localized: "Online"), note: "Whether you're connected, right now.")
                Divider().padding(.leading, 16)
                AnnotatedRow(
                    label: "Wi-Fi", value: "HomeNet", note: "Which network you're on — Wi-Fi, cellular or VPN.")
                Divider().padding(.leading, 16)
                AnnotatedRow(
                    label: "IP address", value: "192.168.178.42", monospaced: true,
                    note: "This iPhone's address on this network — a new one on each network you join.")
                Divider().padding(.leading, 16)
                AnnotatedRow(
                    label: "VPN", value: String(localized: "Active · Full tunnel"),
                    note: "On when a VPN app is connected. Full tunnel routes everything through it.")
            }
        }
    }
}

private struct LANPage: View {
    var body: some View {
        OnboardingPage(
            symbol: "network", title: "Find other devices on this network",
            message:
                "LAN searches your Wi-Fi for other devices — routers, computers, smart devices — by asking them directly. Nothing leaves your iPhone."
        ) {
            MockCard {
                MockRow(label: "Network", value: "192.168.178.0/24", monospaced: true)
                Divider().padding(.leading, 16)
                AnnotatedRow(
                    label: "Router (gateway)", value: "192.168.178.1", monospaced: true,
                    note: "The device that connects this network to the internet.")
                Divider().padding(.leading, 16)
                AnnotatedRow(
                    label: "Device · answers to ping", value: "192.168.178.60", monospaced: true,
                    note: "Tap any device for its address and open ports.")
            }
        }
    }
}

private struct LivePage: View {
    var body: some View {
        OnboardingPage(
            symbol: "waveform.path.ecg", title: "Watch the connection in real time",
            message:
                "Throughput, latency and jitter update once a second while this tab is open. Every change — a new network, a VPN, a different radio technology — is logged below."
        ) {
            MockCard {
                AnnotatedRow(label: "Latency", value: "14 ms", note: "Updates once a second while this tab is open.")
                Divider().padding(.leading, 16)
                AnnotatedRow(label: "Loss", value: "0 %", note: "How many replies didn't come back.")
            }
        }
    }
}

private struct ToolsPage: View {
    var body: some View {
        OnboardingPage(
            symbol: "wrench.and.screwdriver", title: "Ping, Traceroute, DNS and more",
            message: "Nine tools for a closer look. Pick one from the row at the top, enter a host or address, and start."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    chip("Ping", selected: true)
                    chip("Traceroute", selected: false)
                    chip("DNS", selected: false)
                }
                Callout(text: "Nine tools in a row at the top: Ping, Traceroute, DNS, Whois, Ports, TLS, HTTP, Subnet, OUI.")
                MockCard {
                    AnnotatedRow(
                        label: "Target", value: "192.168.178.1", monospaced: true,
                        note: "Type a host or address, then start.")
                }
            }
        }
    }

    private func chip(_ title: LocalizedStringResource, selected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule())
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
}

private struct PrivacyPage: View {
    var body: some View {
        OnboardingPage(
            symbol: "lock.shield", title: "Your data stays on this iPhone",
            message:
                "Pingscape has no account and shows no ads. It contacts the internet only for what you explicitly ask for, and never sends anything else."
        ) {
            VStack(spacing: 10) {
                MockCard {
                    AnnotatedRow(
                        label: "IP address", value: "••••••••",
                        note: "Long-press one value to hide just that one, for example before a screenshot.")
                }
                Text("You can watch this introduction again any time, under About.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Mock pieces

/// A static row, styled like the app's own rows — for these tutorial
/// mockups only. The values are the project's own example data, never a
/// real reading.
private struct MockRow: View {
    let label: LocalizedStringResource
    let value: String
    var monospaced = false

    var body: some View {
        RowLine(label: label, value: value, monospaced: monospaced)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
    }
}

/// A mock row with an arrow pointing at it from an explanation right below.
private struct AnnotatedRow: View {
    let label: LocalizedStringResource
    let value: String
    var monospaced = false
    let note: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RowLine(label: label, value: value, monospaced: monospaced)
            Callout(text: note)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

/// Label left, value right — or stacked when they do not both fit, exactly
/// like the app's own `DataRow`, so a long value never wraps mid-word.
private struct RowLine: View {
    let label: LocalizedStringResource
    let value: String
    var monospaced: Bool

    private var valueText: some View {
        Text(value).font(monospaced ? .system(.body, design: .monospaced) : .body)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                valueText.multilineTextAlignment(.trailing)
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.footnote).foregroundStyle(.secondary)
                valueText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The arrow and short caption pointing at whatever sits directly above it.
private struct Callout: View {
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "arrow.turn.right.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MockCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
