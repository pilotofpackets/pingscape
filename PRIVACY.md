# Privacy

Pingscape has no account, no analytics, no advertising and no server of its own.

**By default the app sends no data anywhere.** It reads the network state of your device (interfaces, routes, DNS servers, proxy, Wi-Fi and cellular status) and shows it on screen. Nothing is stored except a few settings on your device.

## Permissions

- **Location (while in use):** iOS only lets an app read the name of the connected Wi-Fi network if it has this permission. Pingscape does not read or use your location.
- **Local network:** needed to look for devices on your network and to reach your router. Asked for when you first search for devices. Results stay on your device.
- **Photos (add only):** asked for when you first choose "Save image to Photos" in the share menu. Pingscape can only add that image to your photo library. It does not read your photos.

## Lookups that leave the device

**At start: one DNS lookup.** To find out whether the network translates IPv6 to IPv4 (NAT64), the app asks your system DNS server for `ipv4only.arpa`, a fixed name reserved for exactly this check (RFC 7050). Your DNS server, usually your router, may pass the question on to your provider. It carries nothing about you or your device.

Nothing else below happens on its own, except the first group after you agree to it.

**Public IP address and provider.** Off until you agree (a question at first launch, and a switch under About). A tap on "Load" also works once without switching it on. These servers are asked:

- `api.ipify.org` (IPv4) and `api6.ipify.org` (IPv6): return your public IP address. The request carries nothing but the request itself.
- `ipv4.icanhazip.com` and `ipv6.icanhazip.com`: asked only if the matching ipify host does not answer. Same request, same address returned.
- `stat.ripe.net` (RIPEstat, RIPE NCC): gets your public IP address and returns the AS number and its holder. The app names itself with `sourceapp=pingscape`.
- Your system DNS server: is asked for the name that belongs to your public IP address.

Each of these servers sees your public IP address, as with any internet request. Nothing else is sent: no device data, no location.

**Only when you start them.** Every tool sends what you typed and nothing else:

- Ping, traceroute, ports, TLS, HTTP timing, dual stack and DNS go to the target you entered, and DNS to the server you chose (your system's, 1.1.1.1, 8.8.8.8, 9.9.9.9 or your own). Encrypted, it goes to the same providers: over TLS to `one.one.one.one`, `dns.google` or `dns.quad9.net`, over HTTPS to `cloudflare-dns.com`, `dns.google` or `dns.quad9.net`. "Compare servers" sends the same question to all of them at once.
- Traceroute asks your DNS server for the names of the routers on the way, unless you switch that off.
- NAT sends a STUN request to `stun.cloudflare.com`, `stun.l.google.com` and `stun1.l.google.com`, and to your own STUN server if you entered one. They see the public address and port the request came from and send them back.
- NTP asks `time.apple.com`, `time.cloudflare.com` and `pool.ntp.org` for the time, and your own time server if you entered one. The request carries only the time it was sent.
- Whois goes to `whois.iana.org` and on to the registry responsible for the name. RDAP goes to `data.iana.org` (which registry answers) and then to that registry.
- "Check internet" in the External page asks `captive.apple.com`.
- The optional internet ping in the Live tab (off by default) pings the host you enter, once a second.

**On your local network.** The device search pings addresses of your own network and listens for Bonjour, including for service types beyond the ones built into the app, using Apple's multicast networking entitlement. It also sends an SSDP search to the multicast address `239.255.255.250` to find UPnP devices (routers, media servers, printers) and asks each one that answers, and the router's own address directly, for its UPnP description. This never leaves your network.

**Shortcuts, Siri, widgets and Control Center.** The Shortcuts actions (network status and values, network details, VPN check, ping, DNS lookup, port check, certificate expiry, website check, traceroute, path MTU, clock check) run only when you start them and return their result to you. Actions that show addresses or network names need an unlocked device. With "Hide values by default" on, Siri says a placeholder instead of an address or name; the shortcut still gets the real value, as Copy does in the app. When you talk to Siri, Apple processes the request; Pingscape only receives the action and its values. The public address and the provider are only asked for when external requests are on. The widgets read the values you choose (for example online state, IP address, Wi-Fi name, ping time), show the time they were read and hide addresses and names while the device is locked. The Control Center controls read the connection type and open the app. None of them send anything anywhere except the measurement you ask for (ping, DNS, port, TLS, HTTP, traceroute, NTP) and, with your consent, the public address lookup.

The full policy, in English and German, is on the website: `pingscape.app/privacy.html`.

The app's [privacy manifest](App/Resources/PrivacyInfo.xcprivacy) declares nothing used for tracking. It lists "other data" for app functionality, not linked to you, because the public IP lookup above reaches services that may keep their own logs.
