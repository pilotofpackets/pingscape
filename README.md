# Pingscape

**Network & Ping** for iPhone. A free, open-source app that shows as much network information as iOS allows: connection, Wi-Fi, cellular and SIM, VPN and tunnels, devices on your local network, DNS, proxy and routing.

Display only. No account, no ads, no tracking, no backend.

> **Status:** early development. There is no code to build yet.

## Planned

- **Overview:** online status, gateway, DNS, proxy, public IP (on request)
- **Wi-Fi:** SSID, BSSID, vendor, security, addresses, latency to the router
- **Cellular and SIM:** radio technology per SIM, addresses, data counters
- **VPN and tunnels:** whether a VPN is active, tunnel address, MTU, full or split tunnel
- **LAN:** ping sweep and Bonjour discovery of devices on the local network
- **Live:** throughput per interface, latency, jitter and loss
- **Tools:** ping, traceroute, DNS, whois, ports, TLS, HTTP timing, subnet calculator

Native SwiftUI, iOS 18 or later, Liquid Glass on iOS 26 and later. English and German.

## Principles

- Only real data: nothing is guessed, and missing values are simply not shown.
- Private by default: everything runs on the device. Lookups that leave the device happen only with your consent.
- Public Apple APIs only.

## License

[MIT](LICENSE)
