import Darwin
import Foundation

/// Finds UPnP devices on the local network with a real multicast SSDP search.
///
/// Sends the M-SEARCH request to the multicast group `239.255.255.250:1900`,
/// so it reaches every UPnP device on the network (routers, media servers,
/// printers), unlike `UPnPClient.describe(gateway:)`, which only asks the
/// gateway directly. Sending to a multicast address needs Apple's multicast
/// networking entitlement; without it the send fails and the search finds
/// nothing, so LAN discovery keeps working without SSDP.
///
/// The request is sent a few times, not once: a multicast frame gets no
/// link-layer retry on Wi-Fi (unlike unicast), so either our search or a
/// device's reply can simply be lost, and a device may wait up to `MX`
/// seconds before answering at all. Repeating it is what real SSDP control
/// points do for the same reason.
public enum SSDPBrowser {
    public static let searchSeconds = 4.5
    private static let maxSends = 3
    private static let resendGapMilliseconds = 800

    /// One finding per responding device, until the search ends. Devices that
    /// do not answer the description request are left out, same as a device
    /// that does not answer at all.
    public static func browse(duration: Double = searchSeconds) -> AsyncStream<(ip: String, service: LANService)> {
        AsyncStream { continuation in
            let task = Task {
                for (ip, location) in await search(seconds: duration) {
                    guard let url = URL(string: location), let description = await UPnPClient.fetchDescription(at: url)
                    else { continue }
                    continuation.yield((ip, service(from: description, fallbackName: ip)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sends the multicast M-SEARCH, resending it after a gap with no reply,
    /// and collects each responding device's address and description
    /// `LOCATION`, one entry per address.
    private static func search(seconds: Double) async -> [(ip: String, location: String)] {
        (try? await Blocking.run { cancel -> [(ip: String, location: String)] in
            let socket = try POSIXSocket(family: AF_INET, type: SOCK_DGRAM)
            guard let group = ResolvedAddress(literal: "239.255.255.250") else { return [] }
            let request = Array("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: upnp:rootdevice\r\n\r\n".utf8)

            func send() -> Bool {
                let sent = request.withUnsafeBytes { raw in
                    group.withSockaddr(port: 1900) { sa, length in Darwin.sendto(socket.fd, raw.baseAddress, request.count, 0, sa, length) }
                }
                return sent >= 0
            }
            // Without the entitlement this fails (EPERM/EACCES): finish with nothing.
            guard send() else { return [] }

            var found: [(ip: String, location: String)] = []
            var seen = Set<String>()
            let deadline = Deadline(afterMilliseconds: Int(seconds * 1000))
            var sendsLeft = maxSends - 1
            while true {
                // Waits at most until the next resend is due, so a quiet gap
                // triggers another send instead of giving up on the whole search.
                let untilResend = sendsLeft > 0
                    ? Deadline(afterMilliseconds: min(deadline.remainingMilliseconds, resendGapMilliseconds)) : deadline
                do { try socket.wait(for: Int16(POLLIN), deadline: untilResend, cancel: cancel) } catch is CancellationError {
                    break
                } catch {
                    guard sendsLeft > 0, deadline.remainingMilliseconds > 0 else { break }
                    sendsLeft -= 1
                    _ = send()
                    continue
                }
                guard let (reply, from) = socket.receiveFrom(limit: 4096), let ip = ResolvedAddress.text(ofSockaddr: from),
                    seen.insert(ip).inserted,
                    let location = UPnPClient.location(inSearchReply: String(decoding: reply, as: UTF8.self))
                else { continue }
                found.append((ip, location))
            }
            return found
        }) ?? []
    }

    /// A device's description as a service on its list, in the same shape as
    /// a Bonjour finding: the manufacturer, model and firmware it gives go
    /// into the TXT entries, and nothing is guessed for what it leaves out.
    static func service(from description: UPnPClient.Description, fallbackName: String) -> LANService {
        var txt: [String: String] = [:]
        if let manufacturer = description.manufacturer { txt["manufacturer"] = manufacturer }
        if let model = description.model { txt["model"] = model }
        if let firmware = description.firmware { txt["firmware"] = firmware }
        return LANService(type: "upnp:rootdevice", name: description.friendlyName ?? fallbackName, txt: txt)
    }
}
