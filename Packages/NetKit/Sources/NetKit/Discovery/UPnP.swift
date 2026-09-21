import Darwin
import Foundation

/// What a router says about itself over UPnP. A field the router does not
/// give stays `nil`, and the row is left out.
public struct RouterInfo: Sendable, Equatable {
    public let manufacturer: String?
    public let model: String?
    public let firmware: String?
    /// The address the router has on the internet side.
    public let externalIP: String?
    /// Seconds since the internet connection came up.
    public let uptimeSeconds: Int?

    public init(
        manufacturer: String? = nil, model: String? = nil, firmware: String? = nil, externalIP: String? = nil,
        uptimeSeconds: Int? = nil
    ) {
        self.manufacturer = manufacturer
        self.model = model
        self.firmware = firmware
        self.externalIP = externalIP
        self.uptimeSeconds = uptimeSeconds
    }

    public var isEmpty: Bool {
        manufacturer == nil && model == nil && firmware == nil && externalIP == nil && uptimeSeconds == nil
    }
}

/// Reads the UPnP device description of the router and, if it offers the
/// read-only calls, its external address and uptime.
///
/// Everything goes to the gateway's own address by unicast. No multicast, so
/// Apple's multicast entitlement is not needed. Nothing is changed on the router.
public enum UPnPClient {
    public static let timeoutSeconds = 2.0

    struct Description: Equatable {
        var manufacturer: String?
        var modelName: String?
        var modelNumber: String?
        var firmware: String?
        var services: [Service] = []

        struct Service: Equatable {
            let type: String
            let controlPath: String
        }
    }

    /// The router's information, or `nil` if it does not answer over UPnP.
    public static func describe(gateway: String) async -> RouterInfo? {
        guard let base = await locate(gateway: gateway),
            let data = try? await fetch(base, method: "GET"),
            let description = parse(description: data)
        else { return nil }

        var externalIP: String?
        var uptime: Int?
        if let wan = description.services.first(where: { $0.type.contains("WANIPConnection") || $0.type.contains("WANPPPConnection") }),
            let control = URL(string: wan.controlPath, relativeTo: base)?.absoluteURL, control.host == gateway
        {
            if let answer = try? await soap(control, service: wan.type, action: "GetExternalIPAddress") {
                externalIP = value(of: "NewExternalIPAddress", in: answer).flatMap { ToolInput.isIPv4($0) || ToolInput.isIPv6($0) ? $0 : nil }
            }
            if let answer = try? await soap(control, service: wan.type, action: "GetStatusInfo") {
                uptime = value(of: "NewUptime", in: answer).flatMap { Int($0) }
            }
        }

        var model = description.modelName
        if let number = description.modelNumber, !number.isEmpty, model?.contains(number) != true {
            model = [model, number].compactMap { $0 }.joined(separator: " ")
        }
        let info = RouterInfo(
            manufacturer: description.manufacturer, model: model, firmware: description.firmware,
            externalIP: externalIP, uptimeSeconds: uptime)
        return info.isEmpty ? nil : info
    }

    // MARK: Finding the description

    /// Places where routers commonly serve their description, tried when the
    /// router does not answer the unicast search.
    private static let commonPaths: [(port: Int, path: String)] = [
        (49000, "/igddesc.xml"), (1900, "/rootDesc.xml"), (5000, "/rootDesc.xml"), (52869, "/picsdesc.xml"),
        (49152, "/wps_device.xml"), (80, "/rootDesc.xml"),
    ]

    private static func locate(gateway: String) async -> URL? {
        if let location = try? await search(gateway: gateway),
            let url = URL(string: location), url.host == gateway
        {
            return url
        }
        for candidate in commonPaths {
            guard let url = URL(string: "http://\(gateway):\(candidate.port)\(candidate.path)") else { continue }
            if (try? await fetch(url, method: "GET")) != nil { return url }
        }
        return nil
    }

    /// A unicast SSDP search. The router answers with the location of its description.
    private static func search(gateway: String) async throws -> String? {
        guard let address = ResolvedAddress(literal: gateway), !address.isIPv6 else { return nil }
        return try await Blocking.run { cancel in
            let socket = try POSIXSocket(family: AF_INET, type: SOCK_DGRAM)
            let request = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: upnp:rootdevice\r\n\r\n"
            let bytes = Array(request.utf8)
            let sent = bytes.withUnsafeBytes { raw in
                address.withSockaddr(port: 1900) { sa, length in
                    Darwin.sendto(socket.fd, raw.baseAddress, bytes.count, 0, sa, length)
                }
            }
            guard sent >= 0 else { return nil }
            let deadline = Deadline(afterMilliseconds: Int(timeoutSeconds * 1000))
            while true {
                do { try socket.wait(for: Int16(POLLIN), deadline: deadline, cancel: cancel) } catch ToolError.timeout { return nil }
                guard let (reply, from) = socket.receiveFrom(limit: 4096),
                    ResolvedAddress.text(ofSockaddr: from) == gateway,
                    let location = location(inSearchReply: String(decoding: reply, as: UTF8.self))
                else { continue }
                return location
            }
        }
    }

    static func location(inSearchReply text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":"),
                line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "location"
            else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    // MARK: HTTP

    private static func fetch(_ url: URL, method: String, body: Data? = nil, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeoutSeconds)
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 512 * 1024 else {
            throw ToolError.unreadable
        }
        return data
    }

    /// A read-only SOAP call (`GetExternalIPAddress`, `GetStatusInfo`).
    private static func soap(_ url: URL, service: String, action: String) async throws -> Data {
        let envelope = """
            <?xml version="1.0"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body><u:\(action) xmlns:u="\(service)"/></s:Body>
            </s:Envelope>
            """
        return try await fetch(
            url, method: "POST", body: Data(envelope.utf8),
            headers: ["Content-Type": "text/xml; charset=\"utf-8\"", "SOAPAction": "\"\(service)#\(action)\""])
    }

    // MARK: Reading XML

    /// The device fields and the services of a UPnP device description.
    static func parse(description data: Data) -> Description? {
        let reader = DescriptionReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = false
        guard parser.parse() || !reader.result.services.isEmpty || reader.result.manufacturer != nil
        else { return nil }
        return reader.result
    }

    /// The text of the first element with this name.
    static func value(of element: String, in data: Data) -> String? {
        let reader = ValueReader(element: element)
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class DescriptionReader: NSObject, XMLParserDelegate {
        var result = UPnPClient.Description()
        private var path: [String] = []
        private var text = ""
        private var serviceType: String?
        private var controlURL: String?
        private var deviceDepth: Int?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            path.append(name)
            text = ""
            if name == "device", deviceDepth == nil { deviceDepth = path.count }
            if name == "service" { serviceType = nil; controlURL = nil }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Fields of the root device only, not of the devices nested in it.
            let isRootDeviceField = deviceDepth.map { path.count == $0 + 1 } ?? false
            if isRootDeviceField, !value.isEmpty {
                switch name {
                case "manufacturer": result.manufacturer = result.manufacturer ?? value
                case "modelName": result.modelName = result.modelName ?? value
                case "modelNumber": result.modelNumber = result.modelNumber ?? value
                case "firmwareVersion", "softwareVersion": result.firmware = result.firmware ?? value
                default: break
                }
            }
            if path.contains("service"), !value.isEmpty {
                if name == "serviceType" { serviceType = value }
                if name == "controlURL" { controlURL = value }
            }
            if name == "service", let serviceType, let controlURL {
                result.services.append(.init(type: serviceType, controlPath: controlURL))
            }
            path.removeLast()
            text = ""
        }
    }

    private final class ValueReader: NSObject, XMLParserDelegate {
        let element: String
        var text: String?
        private var collecting = false
        private var buffer = ""

        init(element: String) { self.element = element }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            // The element may carry a namespace prefix ("s:Foo").
            if text == nil, name == element || name.hasSuffix(":" + element) {
                collecting = true
                buffer = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { if collecting { buffer += string } }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if collecting, name == element || name.hasSuffix(":" + element) {
                text = buffer
                collecting = false
            }
        }
    }
}
