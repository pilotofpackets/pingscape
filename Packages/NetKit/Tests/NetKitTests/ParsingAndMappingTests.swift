import Foundation
import Network
import Testing

@testable import NetKit

/// The parts of the network tools that need no network: reading what a server
/// sent, what the user typed, and turning system errors into `ToolError`.
@Suite("Whois referrals")
struct WhoisReferralTests {
    @Test("IANA names the registry under refer:")
    func iana() {
        let text = "% IANA WHOIS server\n\ndomain:       DE\n\nrefer:        whois.denic.de\n"
        #expect(WhoisClient.referral(in: text, from: "whois.iana.org", keys: WhoisClient.ianaKeys) == "whois.denic.de")
    }

    @Test("A thin registry names the registrar's server")
    func registrar() {
        let text = "   Domain Name: EXAMPLE.COM\n   Registrar WHOIS Server: whois.iana.org\n"
        #expect(WhoisClient.referral(in: text, from: "whois.verisign-grs.com", keys: WhoisClient.registryKeys) == "whois.iana.org")
    }

    @Test("ARIN's ReferralServer loses its scheme and port")
    func arin() {
        let text = "ReferralServer:  rwhois://rwhois.example.net:4321/\n"
        #expect(WhoisClient.referral(in: text, from: "whois.arin.net", keys: WhoisClient.registryKeys) == "rwhois.example.net")
        let plain = "ReferralServer: whois://whois.ripe.net\n"
        #expect(WhoisClient.referral(in: plain, from: "whois.arin.net", keys: WhoisClient.registryKeys) == "whois.ripe.net")
    }

    @Test("A referral back to the same server, an empty one or no host is ignored")
    func ignored() {
        let keys = WhoisClient.registryKeys
        #expect(WhoisClient.referral(in: "refer: whois.iana.org", from: "whois.iana.org", keys: keys) == nil)
        #expect(WhoisClient.referral(in: "refer:", from: "whois.iana.org", keys: keys) == nil)
        #expect(WhoisClient.referral(in: "refer: localhost", from: "whois.iana.org", keys: keys) == nil)
        #expect(WhoisClient.referral(in: "refer: not a host!", from: "whois.iana.org", keys: keys) == nil)
        #expect(WhoisClient.referral(in: "no colon here", from: "whois.iana.org", keys: keys) == nil)
        #expect(WhoisClient.referral(in: "", from: "whois.iana.org", keys: keys) == nil)
    }

    @Test("Keys are matched without case and only as whole keys")
    func keys() {
        #expect(WhoisClient.referral(in: "REFER: whois.nic.it", from: "whois.iana.org", keys: WhoisClient.ianaKeys) == "whois.nic.it")
        #expect(WhoisClient.referral(in: "referrer: whois.nic.it", from: "whois.iana.org", keys: WhoisClient.ianaKeys) == nil)
    }

    @Test("DENIC and ARIN get the query they need")
    func queries() throws {
        #expect(WhoisClient.query(for: try LookupTarget("example.de"), at: "whois.denic.de") == "-T dn example.de")
        #expect(WhoisClient.query(for: try LookupTarget("8.8.8.8"), at: "whois.arin.net") == "n + 8.8.8.8")
        #expect(WhoisClient.query(for: try LookupTarget("example.com"), at: "whois.arin.net") == "example.com")
        #expect(WhoisClient.query(for: try LookupTarget("AS3320"), at: "whois.ripe.net") == "AS3320")
    }
}

@Suite("Public IP answers")
struct PublicIPTests {
    @Test("An answer is used only if it is an address of the asked family")
    func validated() {
        #expect(PublicIPLookup.validated("203.0.113.57\n", version: .v4) == "203.0.113.57")
        #expect(PublicIPLookup.validated("  2001:db8::1 ", version: .v6) == "2001:db8::1")
        #expect(PublicIPLookup.validated("2001:db8::1", version: .v4) == nil)
        #expect(PublicIPLookup.validated("203.0.113.57", version: .v6) == nil)
        #expect(PublicIPLookup.validated("<html>blocked</html>", version: .v4) == nil)
        #expect(PublicIPLookup.validated("", version: .v4) == nil)
        #expect(PublicIPLookup.validated("999.1.1.1", version: .v4) == nil)
    }
}

@Suite("HTTP tool input and errors")
struct HTTPTimerTests {
    @Test("A bare name becomes an https URL")
    func addsScheme() throws {
        #expect(try HTTPTimer.url(from: "example.com").absoluteString == "https://example.com")
        #expect(try HTTPTimer.url(from: " example.com/path?q=1 ").absoluteString == "https://example.com/path?q=1")
        #expect(try HTTPTimer.url(from: "http://192.168.178.1").absoluteString == "http://192.168.178.1")
        #expect(try HTTPTimer.url(from: "HTTPS://Example.com").host == "Example.com")
    }

    @Test("Other schemes, empty input and broken hosts are turned down")
    func rejects() {
        #expect(throws: InputError.empty) { try HTTPTimer.url(from: "   ") }
        for text in ["ftp://example.com", "https://", "https://exa mple.com", "file:///etc/hosts", "javascript:alert(1)"] {
            #expect(throws: InputError.invalidURL, "\(text)") { try HTTPTimer.url(from: text) }
        }
    }

    @Test("URL errors map to the short reasons the app shows")
    func errors() {
        #expect(HTTPTimer.map(URLError(.timedOut)) == .timeout)
        #expect(HTTPTimer.map(URLError(.cannotFindHost)) == .cannotResolve)
        #expect(HTTPTimer.map(URLError(.dnsLookupFailed)) == .cannotResolve)
        #expect(HTTPTimer.map(URLError(.cannotConnectToHost)) == .refused)
        #expect(HTTPTimer.map(URLError(.notConnectedToInternet)) == .noRoute)
        #expect(HTTPTimer.map(URLError(.networkConnectionLost)) == .noRoute)
        #expect(HTTPTimer.map(URLError(.appTransportSecurityRequiresSecureConnection)) == .insecureConnection)
        #expect(HTTPTimer.map(URLError(.serverCertificateUntrusted)) == .handshakeFailed)
        #expect(HTTPTimer.map(URLError(.serverCertificateHasBadDate)) == .handshakeFailed)
        if case .failed = HTTPTimer.map(URLError(.badServerResponse)) {} else { Issue.record("Other errors keep the system's text") }
        if case .failed = HTTPTimer.map(CocoaError(.fileNoSuchFile)) {} else { Issue.record("A non-URL error keeps its text") }
    }
}

@Suite("TLS names")
struct TLSNameTests {
    @Test("Protocol versions have their usual names")
    func versions() {
        #expect(TLSInspector.versionName(.TLSv12) == "TLS 1.2")
        #expect(TLSInspector.versionName(.TLSv13) == "TLS 1.3")
        #expect(TLSInspector.versionName(.TLSv10) == "TLS 1.0")
        #expect(TLSInspector.versionName(.TLSv11) == "TLS 1.1")
        #expect(TLSInspector.versionName(.DTLSv12) == nil)
    }

    @Test("Known cipher suites by IANA name, others as hex")
    func suites() {
        #expect(TLSInspector.cipherSuiteName(.AES_128_GCM_SHA256) == "TLS_AES_128_GCM_SHA256")
        #expect(TLSInspector.cipherSuiteName(.ECDHE_RSA_WITH_AES_128_GCM_SHA256) == "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256")
        #expect(TLSInspector.cipherSuiteName(.CHACHA20_POLY1305_SHA256) == "TLS_CHACHA20_POLY1305_SHA256")
        #expect(TLSInspector.cipherSuiteName(tls_ciphersuite_t(rawValue: 0x00FF)!) == "0x00FF")
    }
}

@Suite("System errors")
struct ToolErrorTests {
    @Test("POSIX error numbers become the app's reasons")
    func posix() {
        #expect(ToolError(errno: ECONNREFUSED) == .refused)
        #expect(ToolError(errno: ETIMEDOUT) == .timeout)
        for code in [ENETUNREACH, EHOSTUNREACH, ENETDOWN, EHOSTDOWN, EADDRNOTAVAIL] {
            #expect(ToolError(errno: code) == .noRoute, "errno \(code)")
        }
        #expect(ToolError(errno: EPERM) == .notPermitted)
        #expect(ToolError(errno: EACCES) == .notPermitted)
        #expect(ToolError(errno: EINVAL) == .failed(String(cString: strerror(EINVAL))))
    }
}

@Suite("Cellular technology")
struct RadioTechnologyTests {
    @Test("Every Core Telephony constant maps to its generation", arguments: [
        ("CTRadioAccessTechnologyNRNSA", "5G NSA"), ("CTRadioAccessTechnologyNR", "5G"),
        ("CTRadioAccessTechnologyLTE", "4G (LTE)"), ("CTRadioAccessTechnologyWCDMA", "3G"),
        ("CTRadioAccessTechnologyHSDPA", "3G"), ("CTRadioAccessTechnologyHSUPA", "3G"),
        ("CTRadioAccessTechnologyeHRPD", "3G (EVDO)"), ("CTRadioAccessTechnologyCDMAEVDORev0", "3G (EVDO)"),
        ("CTRadioAccessTechnologyCDMAEVDORevA", "3G (EVDO)"), ("CTRadioAccessTechnologyCDMAEVDORevB", "3G (EVDO)"),
        ("CTRadioAccessTechnologyEdge", "2G (EDGE)"), ("CTRadioAccessTechnologyGPRS", "2G (GPRS)"),
        ("CTRadioAccessTechnologyCDMA1x", "2G (CDMA)"), ("CTRadioAccessTechnology6G", "?"), ("", "?"),
    ])
    func mapping(_ raw: String, _ label: String) {
        #expect(RadioTechnology(coreTelephonyValue: raw).label == label)
    }
}
