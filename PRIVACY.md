# Privacy

Pingscape has no account, no analytics, no advertising and no server of its own.

**By default the app sends no data anywhere.** It reads the network state of your device (interfaces, routes, DNS servers, proxy, Wi-Fi and cellular status) and shows it on screen. Nothing is stored except a few settings on your device.

## Permissions

- **Location (while in use):** iOS only lets an app read the name of the connected Wi-Fi network if it has this permission. Pingscape does not read or use your location.
- **Local network:** needed to look for devices on your network and to reach your router. Asked for when you first search for devices. Results stay on your device.

## Lookups that leave the device

Nothing below happens on its own, except the first group after you agree to it.

**Public IP address and provider.** Off until you agree (a question at first launch, and a switch under About). A tap on "Load" also works once without switching it on. These servers are asked:

- `api.ipify.org` (IPv4) and `api6.ipify.org` (IPv6): return your public IP address. The request carries nothing but the request itself.
- `stat.ripe.net` (RIPEstat, RIPE NCC): gets your public IP address and returns the AS number and its holder. The app names itself with `sourceapp=pingscape`.
- Your system DNS server: is asked for the name that belongs to your public IP address.

Each of these servers sees your public IP address, as with any internet request. Nothing else is sent: no device data, no location.

**Only when you start them.** Every tool sends what you typed and nothing else:

- Ping, traceroute, ports, TLS, HTTP timing and DNS go to the target you entered, and DNS to the server you chose (your system's, 1.1.1.1, 8.8.8.8, 9.9.9.9 or your own).
- Traceroute asks your DNS server for the names of the routers on the way, unless you switch that off.
- Whois goes to `whois.iana.org` and on to the registry responsible for the name. RDAP goes to `data.iana.org` (which registry answers) and then to that registry.
- "Check internet" in the External page asks `captive.apple.com`.
- The optional internet ping in the Live tab (off by default) pings the host you enter, once a second.

**On your local network.** The device search pings addresses of your own network and listens for Bonjour. The router's own address is asked for its UPnP description. This never leaves your network.

The app's [privacy manifest](App/Resources/PrivacyInfo.xcprivacy) declares that no data is collected and nothing is used for tracking.
