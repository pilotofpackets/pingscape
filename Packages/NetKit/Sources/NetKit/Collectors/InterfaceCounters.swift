import Darwin

/// Traffic counters of one interface since the device started.
public struct InterfaceCounters: Sendable, Hashable, Codable {
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let receivedPackets: UInt64
    public let sentPackets: UInt64

    public init(receivedBytes: UInt64, sentBytes: UInt64, receivedPackets: UInt64, sentPackets: UInt64) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.receivedPackets = receivedPackets
        self.sentPackets = sentPackets
    }
}

/// Reads 64-bit interface counters from `sysctl NET_RT_IFLIST2`.
///
/// `getifaddrs` hands out `if_data`, whose byte counters are 32 bits wide and
/// wrap after 4 GiB. The `RTM_IFINFO2` messages carry `if_data64` instead.
/// `if_msghdr2` and `if_data64` are in the iOS SDK. Only the message type
/// constant is not, because `net/route.h` is missing.
public enum InterfaceCounterParser {
    /// `RTM_IFINFO2`, from `net/route.h`.
    static let interfaceInfo2: UInt8 = 0x12

    /// The counters by interface index. Messages of other types are skipped.
    public static func counters(in buffer: [UInt8]) -> [Int: InterfaceCounters] {
        var result: [Int: InterfaceCounters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            // Every message starts with `ifm_msglen` (u16), a version and a type.
            while offset + 4 <= raw.count {
                let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, offset + length <= raw.count else { break }
                defer { offset += length }

                guard raw[offset + 3] == interfaceInfo2, length >= MemoryLayout<if_msghdr2>.size
                else { continue }
                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                result[Int(message.ifm_index)] = InterfaceCounters(
                    receivedBytes: message.ifm_data.ifi_ibytes,
                    sentBytes: message.ifm_data.ifi_obytes,
                    receivedPackets: message.ifm_data.ifi_ipackets,
                    sentPackets: message.ifm_data.ifi_opackets)
            }
        }
        return result
    }
}

public enum InterfaceCounterCollector {
    // Stable Darwin constants: CTL_NET, PF_ROUTE. NET_RT_IFLIST2 is in the SDK.
    private static let ctlNet: Int32 = 4
    private static let pfRoute: Int32 = 17

    /// The counters by interface index. Empty if the system does not answer,
    /// so a caller shows no counters rather than wrapped ones.
    public static func collect() -> [Int: InterfaceCounters] {
        var mib: [Int32] = [ctlNet, pfRoute, 0, 0, NET_RT_IFLIST2, 0]
        var needed = 0
        guard sysctl(&mib, 6, nil, &needed, nil, 0) == 0, needed > 0 else { return [:] }

        // The list can grow between the two calls. Leave some room.
        needed += needed / 4
        var buffer = [UInt8](repeating: 0, count: needed)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return sysctl(&mib, 6, base, &needed, nil, 0) == 0
        }
        guard ok, needed > 0 else { return [:] }
        return InterfaceCounterParser.counters(in: Array(buffer[..<needed]))
    }
}
