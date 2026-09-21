import Foundation
import Testing

@testable import NetKit

@Suite("Lookup targets")
struct LookupTargetTests {
    @Test func readsDomainsAddressesAndASNumbers() throws {
        #expect(try LookupTarget("Example.com") == .domain("example.com"))
        #expect(try LookupTarget("https://example.com/path") == .domain("example.com"))
        #expect(try LookupTarget("203.0.113.57") == .ip("203.0.113.57"))
        #expect(try LookupTarget("2001:db8::1") == .ip("2001:db8::1"))
        #expect(try LookupTarget("AS64500") == .asn(64500))
        #expect(try LookupTarget("as3333") == .asn(3333))
        #expect(try LookupTarget("3333") == .asn(3333))
        #expect(try LookupTarget("AS64500").whoisQuery == "AS64500")
    }

    @Test(arguments: ["", "exa mple", "999.1.1.1"])
    func rejectsBrokenTargets(_ text: String) {
        #expect(throws: InputError.self) { try LookupTarget(text) }
    }
}

@Suite("Whois")
struct WhoisTests {
    @Test func followsTheIANAReferral() {
        let iana = """
            % IANA WHOIS server
            domain:       COM

            organisation: VeriSign Global Registry Services
            refer:        whois.verisign-grs.com

            whois:        whois.verisign-grs.com
            status:       ACTIVE
            """
        #expect(WhoisClient.referral(in: iana, from: "whois.iana.org", keys: WhoisClient.ianaKeys) == "whois.verisign-grs.com")
    }

    @Test func followsARegistrarFromAThinRegistry() {
        let registry = """
               Domain Name: EXAMPLE.COM
               Registrar WHOIS Server: whois.registrar.example
               Registrar URL: http://registrar.example
            """
        #expect(WhoisClient.referral(in: registry, from: "whois.verisign-grs.com", keys: WhoisClient.registryKeys) == "whois.registrar.example")
    }

    @Test func readsARWhoisReferralWithSchemePortAndPath() {
        #expect(WhoisClient.referral(in: "ReferralServer: whois://whois.ripe.net:43", from: "whois.arin.net", keys: WhoisClient.registryKeys) == "whois.ripe.net")
        #expect(WhoisClient.referral(in: "ReferralServer: rwhois://rwhois.example.net:4321/", from: "whois.arin.net", keys: WhoisClient.registryKeys) == "rwhois.example.net")
    }

    @Test func asksTheRegistryInItsOwnFormat() throws {
        let domain = try LookupTarget("example.de")
        #expect(WhoisClient.query(for: domain, at: "whois.denic.de") == "-T dn example.de")
        #expect(WhoisClient.query(for: domain, at: "whois.verisign-grs.com") == "example.de")
        #expect(WhoisClient.query(for: try LookupTarget("8.8.8.8"), at: "whois.arin.net") == "n + 8.8.8.8")
        #expect(WhoisClient.query(for: try LookupTarget("AS3333"), at: "whois.ripe.net") == "AS3333")
    }

    @Test func doesNotLoopOrFollowJunk() {
        #expect(WhoisClient.referral(in: "refer: whois.iana.org", from: "whois.iana.org", keys: WhoisClient.ianaKeys) == nil)
        #expect(WhoisClient.referral(in: "Registrar WHOIS Server:", from: "x.example", keys: WhoisClient.registryKeys) == nil)
        #expect(WhoisClient.referral(in: "refer: not a host", from: "x.example", keys: WhoisClient.ianaKeys) == nil)
        #expect(WhoisClient.referral(in: "nothing here", from: "x.example", keys: WhoisClient.ianaKeys) == nil)
    }
}

@Suite("RDAP")
struct RDAPTests {
    private func bootstrap(_ json: String) throws -> RDAPClient.Bootstrap {
        try RDAPClient.Bootstrap(json: Data(json.utf8))
    }

    @Test func findsTheServerOfATopLevelDomain() throws {
        let dns = try bootstrap(RDAPFixtures.dnsBootstrap)
        #expect(dns.url(forDomain: "example.com") == "https://rdap.verisign.com/com/v1/")
        #expect(dns.url(forDomain: "WWW.Example.COM") == "https://rdap.verisign.com/com/v1/")
        #expect(dns.url(forDomain: "example.zzzz") == nil)
    }

    @Test func findsTheRegistryOfAnAddress() throws {
        let v4 = try bootstrap(RDAPFixtures.ipv4Bootstrap)
        #expect(v4.url(forIP: "193.0.6.139") == "https://rdap.db.ripe.net/")
        #expect(v4.url(forIP: "1.1.1.1") == "https://rdap.apnic.net/")
        #expect(v4.url(forIP: "8.8.8.8") == "https://rdap.arin.net/registry/")
        #expect(v4.url(forIP: "41.0.0.1") == "https://rdap.afrinic.net/rdap/")
        let v6 = try bootstrap(RDAPFixtures.ipv6Bootstrap)
        #expect(v6.url(forIP: "2001:67c:2e8:22::c100:68b") == "https://rdap.db.ripe.net/")
        #expect(v6.url(forIP: "2606:4700:4700::1111") == "https://rdap.arin.net/registry/")
    }

    @Test func findsTheRegistryOfAnASNumber() throws {
        let asn = try bootstrap(RDAPFixtures.asnBootstrap)
        #expect(asn.url(forASN: 3333) == "https://rdap.db.ripe.net/")
        #expect(asn.url(forASN: 13335) == "https://rdap.arin.net/registry/")
        #expect(asn.url(forASN: 36864) == "https://rdap.afrinic.net/rdap/")
    }

    @Test func readsADomainAnswer() throws {
        let result = try RDAPClient.parse(Data(RDAPFixtures.domain.utf8), server: "rdap.verisign.com")
        #expect(result.name == "EXAMPLE.COM")
        #expect(result.handle == "2336799_DOMAIN_COM-VRSN")
        #expect(result.status == ["client delete prohibited", "client transfer prohibited", "client update prohibited"])
        #expect(result.registrar == "RESERVED-Internet Assigned Numbers Authority")
        #expect(result.nameservers == ["ELLIOTT.NS.CLOUDFLARE.COM", "HERA.NS.CLOUDFLARE.COM"])
        // "last update of RDAP database" is about the server, not the domain.
        #expect(
            result.events == [
                RDAPEvent(action: .registration, date: "1995-08-14T04:00:00Z"),
                RDAPEvent(action: .expiration, date: "2027-08-13T04:00:00Z"),
                RDAPEvent(action: .lastChanged, date: "2026-08-14T08:01:43Z"),
            ])
        #expect(result.range == nil)
    }

    @Test func readsAnIPNetworkAnswer() throws {
        let result = try RDAPClient.parse(Data(RDAPFixtures.ip.utf8), server: "rdap.db.ripe.net")
        #expect(result.name == "RIPE-NCC")
        #expect(result.range == "193.0.0.0 – 193.0.7.255")
        #expect(result.status == ["active"])
        #expect(result.registrar == nil && result.nameservers.isEmpty)
    }

    @Test func readsAnASNAnswer() throws {
        let result = try RDAPClient.parse(Data(RDAPFixtures.asn.utf8), server: "rdap.db.ripe.net")
        #expect(result.name == "RIPE-NCC-AS")
        #expect(result.range == "AS3333")
    }

    @Test func rejectsAnswersThatAreNoObjects() {
        #expect(throws: (any Error).self) { try RDAPClient.parse(Data("[1,2]".utf8), server: "x") }
        #expect(throws: (any Error).self) { try RDAPClient.parse(Data("not json".utf8), server: "x") }
    }
}

@Suite("RIPEstat")
struct RIPEstatTests {
    @Test func readsTheNetworkOfAPublicAddress() throws {
        let info = try RIPEstat.networkInfo(Data(RIPEstatFixtures.networkInfo.utf8))
        #expect(info.asns == ["13335"])
        #expect(info.prefix == "1.1.1.0/24")
        let v6 = try RIPEstat.networkInfo(Data(RIPEstatFixtures.networkInfoIPv6.utf8))
        #expect(v6.asns == ["13335"])
        #expect(v6.prefix == "2606:4700:4700::/48")
    }

    @Test func readsThePrivateAddressAsNotAnnounced() throws {
        let info = try RIPEstat.networkInfo(Data(RIPEstatFixtures.networkInfoPrivate.utf8))
        #expect(info.asns.isEmpty)
        #expect(info.prefix == nil)
    }

    @Test func readsTheHolder() throws {
        #expect(try RIPEstat.holder(Data(RIPEstatFixtures.asOverview.utf8)) == "CLOUDFLARENET - Cloudflare, Inc.")
        // An empty holder is no holder.
        #expect(try RIPEstat.holder(Data(RIPEstatFixtures.asOverviewUnknown.utf8)) == nil)
        #expect(try RIPEstat.holder(Data(#"{"status":"ok","data":{"holder":null}}"#.utf8)) == nil)
    }

    @Test func readsANumericASNumber() throws {
        let json = #"{"status":"ok","data":{"asns":[64500],"prefix":"203.0.113.0/24"}}"#
        #expect(try RIPEstat.networkInfo(Data(json.utf8)).asns == ["64500"])
    }

    @Test func rejectsAnswersThatAreNotOK() {
        let error = #"{"status":"error","status_code":500,"message":"boom"}"#
        let maintenance = #"{"status":"maintenance","data":null}"#
        #expect(throws: (any Error).self) { try RIPEstat.networkInfo(Data(error.utf8)) }
        #expect(throws: (any Error).self) { try RIPEstat.holder(Data(maintenance.utf8)) }
        #expect(throws: (any Error).self) { try RIPEstat.holder(Data("<html>".utf8)) }
    }
}

@Suite("Public IP and internet check")
struct ExternalTests {
    @Test func acceptsOnlyAnAddressOfTheAskedVersion() {
        #expect(PublicIPLookup.validated("203.0.113.57\n", version: .v4) == "203.0.113.57")
        #expect(PublicIPLookup.validated("203.0.113.57", version: .v6) == nil)
        #expect(PublicIPLookup.validated("2001:db8::57", version: .v6) == "2001:db8::57")
        #expect(PublicIPLookup.validated("2001:db8::57", version: .v4) == nil)
        #expect(PublicIPLookup.validated("<html>rate limited</html>", version: .v4) == nil)
        #expect(PublicIPLookup.validated("", version: .v4) == nil)
    }

    @Test func tellsAPortalFromTheInternet() {
        let success = "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"
        #expect(InternetCheck.classify(status: 200, body: success) == .reachable)
        #expect(InternetCheck.classify(status: 302, body: "") == .captivePortal)
        #expect(InternetCheck.classify(status: 200, body: "<html>Please sign in</html>") == .captivePortal)
    }
}
