import Darwin
import Foundation

/// The interface a test's packets really used, as the system reports it for
/// the socket that carried them. No prediction from the routing table: with
/// split tunnels and per-app VPN only the socket itself knows.
///
/// Two sources, depending on the socket:
/// - A datagram that arrived (ICMP replies) carries its arrival interface
///   (`IP_RECVIF`, `IPV6_PKTINFO`).
/// - A connected socket (TCP, UDP) has a local address, and that address
///   belongs to one interface.
enum UsedInterface {
    /// The interface that holds `ip`. `nil` if none or more than one does,
    /// since then the address does not tell.
    static func holding(localAddress ip: String) -> String? {
        let holders = InterfaceCollector.collect().filter { interface in
            interface.addresses.contains { $0.ip == ip }
        }
        return holders.count == 1 ? holders[0].name : nil
    }

    static func name(index: UInt32) -> String? {
        guard index > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(index, &buffer) != nil else { return nil }
        return String(nulTerminated: buffer)
    }

    /// `IPV6_RECVPKTINFO` and `IPV6_PKTINFO` from <netinet6/in6.h>, which
    /// Swift does not see without `__APPLE_USE_RFC_3542`.
    static let ipv6ReceivePacketInfo: Int32 = 61
    static let ipv6PacketInfo: Int32 = 46

    /// The arrival interface in the control messages of `recvmsg`.
    static func arrivalInterface(control: UnsafeRawBufferPointer, length: Int) -> String? {
        guard let base = control.baseAddress else { return nil }
        let headerSize = MemoryLayout<cmsghdr>.size
        let alignedHeader = (headerSize + 3) & ~3
        var offset = 0
        while offset + headerSize <= min(length, control.count) {
            let header = base.advanced(by: offset).loadUnaligned(as: cmsghdr.self)
            let size = Int(header.cmsg_len)
            guard size >= headerSize, offset + size <= control.count else { return nil }
            let data = base.advanced(by: offset + alignedHeader)
            if header.cmsg_level == IPPROTO_IP, header.cmsg_type == IP_RECVIF, size >= alignedHeader + 4 {
                // sockaddr_dl: length, family, then the 16-bit interface index.
                let index = data.loadUnaligned(fromByteOffset: 2, as: UInt16.self)
                return name(index: UInt32(index))
            }
            if header.cmsg_level == IPPROTO_IPV6, header.cmsg_type == ipv6PacketInfo,
                size >= alignedHeader + MemoryLayout<in6_pktinfo>.size
            {
                return name(index: data.loadUnaligned(as: in6_pktinfo.self).ipi6_ifindex)
            }
            offset += (size + 3) & ~3
        }
        return nil
    }
}

extension POSIXSocket {
    /// The local address the system gave this socket, after a connect.
    func localAddressText() -> String? {
        var local = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let named = withUnsafeMutablePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { return nil }
        let bytes = withUnsafeBytes(of: &local) { Array($0.prefix(Int(length))) }
        guard let text = ResolvedAddress.text(ofSockaddr: bytes), text != "0.0.0.0", text != "::" else { return nil }
        return text
    }

    /// The interface holding the local address of this connected socket.
    func usedInterface() -> String? {
        localAddressText().flatMap(UsedInterface.holding(localAddress:))
    }

    /// Asks the system to name the arrival interface of every datagram.
    func reportArrivalInterface(ipv6: Bool) {
        var on: Int32 = 1
        if ipv6 {
            setsockopt(
                fd, IPPROTO_IPV6, UsedInterface.ipv6ReceivePacketInfo, &on, socklen_t(MemoryLayout<Int32>.size))
        } else {
            setsockopt(fd, IPPROTO_IP, IP_RECVIF, &on, socklen_t(MemoryLayout<Int32>.size))
        }
    }

    /// One datagram, the address it came from and the interface it arrived
    /// on (with `reportArrivalInterface` set).
    func receiveMessage(limit: Int) -> (bytes: [UInt8], from: [UInt8], interface: String?)? {
        var buffer = [UInt8](repeating: 0, count: limit)
        var control = [UInt8](repeating: 0, count: 128)
        var from = sockaddr_storage()
        var result: (count: Int, fromLength: Int, controlLength: Int) = (0, 0, 0)
        buffer.withUnsafeMutableBytes { bytes in
            control.withUnsafeMutableBytes { controlBytes in
                withUnsafeMutablePointer(to: &from) { fromPointer in
                    var vector = iovec(iov_base: bytes.baseAddress, iov_len: limit)
                    withUnsafeMutablePointer(to: &vector) { vectorPointer in
                        var message = msghdr(
                            msg_name: UnsafeMutableRawPointer(fromPointer),
                            msg_namelen: socklen_t(MemoryLayout<sockaddr_storage>.size),
                            msg_iov: vectorPointer, msg_iovlen: 1,
                            msg_control: controlBytes.baseAddress, msg_controllen: socklen_t(controlBytes.count),
                            msg_flags: 0)
                        let count = recvmsg(fd, &message, 0)
                        result = (count, Int(message.msg_namelen), count > 0 ? Int(message.msg_controllen) : 0)
                    }
                }
            }
        }
        guard result.count > 0 else { return nil }
        let fromBytes = withUnsafeBytes(of: &from) { Array($0.prefix(result.fromLength)) }
        let interface = control.withUnsafeBytes {
            UsedInterface.arrivalInterface(control: $0, length: result.controlLength)
        }
        return (Array(buffer.prefix(result.count)), fromBytes, interface)
    }
}
