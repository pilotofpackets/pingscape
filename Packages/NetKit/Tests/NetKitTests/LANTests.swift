import Foundation
import Testing

@testable import NetKit

@Suite("LAN devices")
struct LANDeviceTests {
    @Test func attachesLateInformationToTheDeviceByAddress() {
        var list = LANDeviceList()
        list.apply(.ping(ip: "192.168.178.40", milliseconds: 4))
        list.apply(.hostname(ip: "192.168.178.40", name: "tv.fritz.box"))
        list.apply(.service(ip: "192.168.178.40", LANService(type: "_airplay._tcp", name: "Living Room TV", port: 7000, txt: ["deviceid": "3c:a6:2f:1b:00:1f"])))
        list.apply(.ports(ip: "192.168.178.40", [443, 80]))
        #expect(list.devices.count == 1)
        let device = list.devices[0]
        #expect(device.answeredPing && device.latencyMilliseconds == 4)
        #expect(device.hostname == "tv.fritz.box")
        #expect(device.displayName == "Living Room TV")
        #expect(device.macAddress == "3C:A6:2F:1B:00:1F")
        #expect(device.openPorts == [80, 443])
    }

    @Test func listsADeviceThatOnlyBonjourFound() {
        var list = LANDeviceList()
        list.apply(.service(ip: "192.168.178.60", LANService(type: "_smb._tcp", name: "nas")))
        #expect(list.devices.map(\.ip) == ["192.168.178.60"])
        #expect(list.devices[0].answeredPing == false)
        #expect(list.devices[0].displayName == "nas")
    }

    @Test func doesNotDuplicateAService() {
        var list = LANDeviceList()
        let service = LANService(type: "_ipp._tcp", name: "Printer", port: 631)
        list.apply(.service(ip: "192.168.178.52", service))
        list.apply(.service(ip: "192.168.178.52", service))
        #expect(list.devices[0].services.count == 1)
    }

    @Test func ordersThisDeviceThenTheRouterThenByAddress() {
        var list = LANDeviceList()
        for ip in ["192.168.178.100", "192.168.178.9", "192.168.178.1", "192.168.178.42"] {
            list.apply(.ping(ip: ip, milliseconds: 1))
        }
        let sorted = list.sorted(thisDevice: "192.168.178.42", gateway: "192.168.178.1")
        #expect(sorted.map(\.ip) == ["192.168.178.42", "192.168.178.1", "192.168.178.9", "192.168.178.100"])
        // A name arriving later does not move anything.
        list.apply(.hostname(ip: "192.168.178.100", name: "a-first.example"))
        #expect(list.sorted(thisDevice: "192.168.178.42", gateway: "192.168.178.1").map(\.ip) == sorted.map(\.ip))
    }

    @Test func readsMACAddressesOnlyWhereTheProtocolDefinesOne() {
        #expect(LANService(type: "_airplay._tcp", name: "TV", txt: ["deviceid": "3C:A6:2F:1B:00:1F"]).announcedMAC == "3C:A6:2F:1B:00:1F")
        #expect(LANService(type: "_workstation._tcp", name: "host [3c:a6:2f:1b:00:1f]").announcedMAC == "3C:A6:2F:1B:00:1F")
        #expect(LANService(type: "_workstation._tcp", name: "host [3c:a6:2f:1b:00:1f]").displayName == "host")
        #expect(LANService(type: "_raop._tcp", name: "3CA62F1B001F@Living Room").announcedMAC == "3C:A6:2F:1B:00:1F")
        #expect(LANService(type: "_raop._tcp", name: "3CA62F1B001F@Living Room").displayName == "Living Room")
        // HomeKit's id looks like a MAC address but is random: not read.
        #expect(LANService(type: "_hap._tcp", name: "Lamp", txt: ["id": "3C:A6:2F:1B:00:1F"]).announcedMAC == nil)
        #expect(LANService(type: "_raop._tcp", name: "no-mac-here").announcedMAC == nil)
    }

    @Test func prefersTheNameTheUserGaveTheDevice() {
        let device = LANDevice(
            ip: "192.168.178.70",
            services: [
                LANService(type: "_http._tcp", name: "webserver"),
                LANService(type: "_googlecast._tcp", name: "Chromecast-abc123", txt: ["fn": "Kitchen display"]),
            ])
        #expect(device.displayName == "Kitchen display")
    }
}

@Suite("LAN search range")
struct LANRangeTests {
    @Test func searchesAllHostsOfASmallNetworkExceptThisDevice() throws {
        let range = try #require(IPv4Range(ip: "192.168.178.42", prefix: 24))
        let (addresses, capped) = LANScanner.addresses(in: range, around: "192.168.178.42")
        #expect(!capped)
        #expect(addresses.count == 253)
        #expect(!addresses.contains("192.168.178.42"))
        #expect(addresses.first == "192.168.178.1" && addresses.last == "192.168.178.254")
    }

    @Test func cutsALargeNetworkToTheBlockAroundThisDevice() throws {
        let range = try #require(IPv4Range(ip: "10.1.6.20", prefix: 16))
        let (addresses, capped) = LANScanner.addresses(in: range, around: "10.1.6.20")
        #expect(capped)
        #expect(addresses.count == 1023)
        #expect(addresses.contains("10.1.4.0") && addresses.contains("10.1.7.255"))
        #expect(!addresses.contains("10.1.3.255") && !addresses.contains("10.1.8.0"))
        #expect(!addresses.contains("10.1.6.20"))
    }

    @Test func leavesOutTheNetworkAndBroadcastAddressOfALargeNetwork() throws {
        let range = try #require(IPv4Range(ip: "10.1.0.9", prefix: 16))
        let (first, _) = LANScanner.addresses(in: range, around: "10.1.0.9")
        #expect(!first.contains("10.1.0.0"))
        let edge = try #require(IPv4Range(ip: "10.1.255.9", prefix: 16))
        let (last, _) = LANScanner.addresses(in: edge, around: "10.1.255.9")
        #expect(!last.contains("10.1.255.255"))
    }
}

@Suite("UPnP")
struct UPnPTests {
    private let description = """
        <?xml version="1.0"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <specVersion><major>1</major><minor>0</minor></specVersion>
          <device>
            <deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:1</deviceType>
            <friendlyName>Example Router</friendlyName>
            <manufacturer>Example Networks</manufacturer>
            <modelName>ER-7000</modelName>
            <modelNumber>7000</modelNumber>
            <softwareVersion>1.2.3</softwareVersion>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:Layer3Forwarding:1</serviceType>
                <controlURL>/upnp/control/L3F</controlURL>
              </service>
            </serviceList>
            <deviceList>
              <device>
                <deviceType>urn:schemas-upnp-org:device:WANDevice:1</deviceType>
                <manufacturer>Nested Maker</manufacturer>
                <deviceList>
                  <device>
                    <serviceList>
                      <service>
                        <serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>
                        <controlURL>/upnp/control/WANIPConn1</controlURL>
                      </service>
                    </serviceList>
                  </device>
                </deviceList>
              </device>
            </deviceList>
          </device>
        </root>
        """

    @Test func readsTheRootDeviceAndItsServices() throws {
        let parsed = try #require(UPnPClient.parse(description: Data(description.utf8)))
        #expect(parsed.manufacturer == "Example Networks")
        #expect(parsed.modelName == "ER-7000")
        #expect(parsed.modelNumber == "7000")
        #expect(parsed.firmware == "1.2.3")
        #expect(parsed.services.map(\.controlPath) == ["/upnp/control/L3F", "/upnp/control/WANIPConn1"])
        #expect(parsed.services.last?.type == "urn:schemas-upnp-org:service:WANIPConnection:1")
    }

    @Test func readsSOAPValuesWithAndWithoutPrefix() {
        let answer = """
            <?xml version="1.0"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>
            <u:GetExternalIPAddressResponse xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">
            <NewExternalIPAddress>203.0.113.57</NewExternalIPAddress></u:GetExternalIPAddressResponse>
            </s:Body></s:Envelope>
            """
        #expect(UPnPClient.value(of: "NewExternalIPAddress", in: Data(answer.utf8)) == "203.0.113.57")
        #expect(UPnPClient.value(of: "NewUptime", in: Data(answer.utf8)) == nil)
        #expect(UPnPClient.value(of: "Foo", in: Data("<a:Foo>bar</a:Foo>".utf8)) == "bar")
    }

    @Test func findsTheLocationInASearchReply() {
        let reply = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=120\r\nLocation: http://192.0.2.1:49000/igddesc.xml\r\nST: upnp:rootdevice\r\n\r\n"
        #expect(UPnPClient.location(inSearchReply: reply) == "http://192.0.2.1:49000/igddesc.xml")
        #expect(UPnPClient.location(inSearchReply: "HTTP/1.1 200 OK\r\n\r\n") == nil)
    }
}
