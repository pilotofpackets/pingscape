# Pingscape

**Network & Ping** for iPhone. A free, open-source app that shows as much network information as iOS allows: connection, Wi-Fi, cellular and SIM, VPN and tunnels, devices on your local network, DNS, proxy and routing.

Display only. No account, no ads, no tracking, no backend.

> **Status:** all planned screens are built and checked in the simulator and on a Mac. Not yet checked on a real iPhone: Wi-Fi name, cellular, VPN detection with WireGuard and IKEv2, and the Local Network behaviour. Expect rough edges there.

## Features

- **Overview:** online status, gateway, DNS, proxy, public IP and provider (only with your consent). Every value can be copied, the overview can be shared as a text report, and "Hide values" keeps addresses out of screenshots.
- **Wi-Fi:** SSID, BSSID, vendor, security, addresses, latency to the router, router details over UPnP
- **Cellular and SIM:** radio technology per SIM, addresses, data counters
- **VPN and tunnels:** whether a VPN is active, tunnel address, MTU, full or split tunnel
- **LAN:** ping sweep and Bonjour discovery of devices on the local network, with a thorough mode that also probes a few TCP ports
- **Live:** throughput per interface, latency, jitter and loss, and a timeline of network changes (foreground only, kept in memory)
- **Tools:** ping, traceroute, DNS, whois and RDAP, ports, TLS certificate, HTTP timing, subnet calculator, OUI lookup
- **Diagnostic dump:** the raw collector data as JSON, with addresses replaced, for reporting a wrong reading

Native SwiftUI, iOS 18 or later, Liquid Glass on iOS 26 and later. English and German.

## Build

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: `brew install xcodegen`, `xcodegen generate`, open `Pingscape.xcodeproj`. Launch with `-demo` to use fixture data in the simulator.

## Principles

- Only real data: nothing is guessed, and missing values are simply not shown.
- Private by default: everything runs on the device. Lookups that leave the device happen only with your consent.
- Public Apple APIs only.

## License

[MIT](LICENSE)
