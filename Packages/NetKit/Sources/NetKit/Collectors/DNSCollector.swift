import Darwin

/// Reads the system resolvers.
///
/// They live only in libresolv. The symbols are looked up at run time, so
/// there is no link dependency, and a missing symbol means an empty result
/// instead of a crash. The resolvers are system wide, not per interface. With a
/// full-tunnel VPN they are the ones of the VPN.
public enum DNSCollector {
    private typealias ResInit = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias ResGetServers = @convention(c) (
        UnsafeMutableRawPointer, UnsafeMutableRawPointer, Int32
    ) -> Int32
    private typealias ResDestroy = @convention(c) (UnsafeMutableRawPointer) -> Void

    public static func servers() -> [String] {
        // RTLD_DEFAULT on Darwin.
        var handle = UnsafeMutableRawPointer(bitPattern: -2)
        var opened: UnsafeMutableRawPointer?
        if dlsym(handle, "res_9_ninit") == nil {
            opened = dlopen("/usr/lib/libresolv.9.dylib", RTLD_NOW)
            handle = opened
        }
        defer { if let opened { dlclose(opened) } }

        guard let initSymbol = dlsym(handle, "res_9_ninit"),
            let serversSymbol = dlsym(handle, "res_9_getservers")
        else { return [] }
        let resInit = unsafeBitCast(initSymbol, to: ResInit.self)
        let resGetServers = unsafeBitCast(serversSymbol, to: ResGetServers.self)

        // `__res_state` is large and undocumented: reserve generously and zero it.
        let stateSize = 8192
        let state = UnsafeMutableRawPointer.allocate(byteCount: stateSize, alignment: 16)
        state.initializeMemory(as: UInt8.self, repeating: 0, count: stateSize)
        defer {
            if let destroySymbol = dlsym(handle, "res_9_ndestroy") {
                unsafeBitCast(destroySymbol, to: ResDestroy.self)(state)
            }
            state.deallocate()
        }
        guard resInit(state) == 0 else { return [] }

        // `union res_sockaddr_union` is 128 bytes (a sockaddr_in6 with reserve).
        let unionSize = 128
        let maxServers = 8
        let servers = UnsafeMutableRawPointer.allocate(byteCount: unionSize * maxServers, alignment: 16)
        servers.initializeMemory(as: UInt8.self, repeating: 0, count: unionSize * maxServers)
        defer { servers.deallocate() }

        let found = resGetServers(state, servers, Int32(maxServers))
        guard found > 0 else { return [] }

        var result: [String] = []
        for index in 0..<Int(min(found, Int32(maxServers))) {
            let sa = servers.advanced(by: index * unionSize).assumingMemoryBound(to: sockaddr.self)
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6,
                let ip = SocketAddress.numericHost(sa), !ip.isEmpty, !result.contains(ip)
            else { continue }
            result.append(ip)
        }
        return result
    }
}
