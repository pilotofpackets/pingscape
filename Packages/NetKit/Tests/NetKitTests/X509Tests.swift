import Foundation
import Testing

@testable import NetKit

/// Certificates made with OpenSSL for these tests. The first is self-signed
/// (UTCTime dates, alternative names of every kind the parser reads), the
/// second is issued by the first and ends in 2059 (GeneralizedTime).
private enum Certificates {
    static let selfSigned = "MIIB6jCCAZGgAwIBAgIDGis8MAoGCCqGSM49BAMCMEMxCzAJBgNVBAYTAkRFMRswGQYDVQQKDBJQaW5nc2NhcGUgVGVzdCBPcmcxFzAVBgNVBAMMDnBpbmdzY2FwZS50ZXN0MB4XDTI2MDkyMTEwMjA1M1oXDTM2MDkxODEwMjA1M1owQzELMAkGA1UEBhMCREUxGzAZBgNVBAoMElBpbmdzY2FwZSBUZXN0IE9yZzEXMBUGA1UEAwwOcGluZ3NjYXBlLnRlc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAShRc8gCHjqBuhUEGMNMIw3+Y33HMVaS75sHk1zKCrSJoi4pYV24FeBaK13l7cVfMP1qIIDDA48W4CV7kWrogdao3QwcjBDBgNVHREEPDA6gg5waW5nc2NhcGUudGVzdIIQKi5waW5nc2NhcGUudGVzdIcEwAACAYcQIAENuAAAAAAAAAAAAAAAATAMBgNVHRMBAf8EAjAAMB0GA1UdDgQWBBSYfwQnrRP7z7KQL13+zaCmVBsNpDAKBggqhkjOPQQDAgNHADBEAiAxRL1AMacfknTWH0VpYI85ibDoSSbya6d8GGcuL3SKJgIgCBHALPONFkLyxJ8SdsNb6nOdwl/SDyjFWdfOaqw/UGw="
    static let leaf = "MIIBkzCCATqgAwIBAgIBBTAKBggqhkjOPQQDAjBDMQswCQYDVQQGEwJERTEbMBkGA1UECgwSUGluZ3NjYXBlIFRlc3QgT3JnMRcwFQYDVQQDDA5waW5nc2NhcGUudGVzdDAgFw0yNjA5MjExMDIwNTNaGA8yMDU5MDczMDEwMjA1M1owHjEcMBoGA1UEAwwTbGVhZi5waW5nc2NhcGUudGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABM2+6+UTakJtBwhuyKuSnHDdqqoq6G+cvnYupL2RoQ8f4R795sTyTgnSX6Oc68NewybJjJHdSeTaCmLA8cK9KJqjQjBAMB0GA1UdDgQWBBSwK1PgzZDSbzAefQewpk+bRsU5GzAfBgNVHSMEGDAWgBSYfwQnrRP7z7KQL13+zaCmVBsNpDAKBggqhkjOPQQDAgNHADBEAiAQ6ly0LVYpMKBKUZEHQUpenkV4Wko8/iz6FQNJeGoDEQIgBEthG6FguGAzMOlhEudcZM/+FUlZPxS9OYQOIV/CTGg="

    static func der(_ base64: String) -> [UInt8] { [UInt8](Data(base64Encoded: base64)!) }
}

@Suite("X.509 parser")
struct X509Tests {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    @Test func readsASelfSignedCertificate() throws {
        let info = try #require(X509.parse(der: Certificates.der(Certificates.selfSigned)))
        #expect(info.subjectName == "pingscape.test")
        #expect(info.subjectOrganization == "Pingscape Test Org")
        #expect(info.issuerName == "pingscape.test")
        #expect(info.isSelfIssued)
        #expect(info.serialNumber == "1A:2B:3C")
        #expect(info.notBefore == date(2026, 9, 21, 10, 20, 53))
        #expect(info.notAfter == date(2036, 9, 18, 10, 20, 53))
        #expect(info.alternativeNames == ["pingscape.test", "*.pingscape.test", "192.0.2.1", "2001:db8::1"])
    }

    @Test func readsAnIssuedCertificateWithGeneralizedTime() throws {
        let info = try #require(X509.parse(der: Certificates.der(Certificates.leaf)))
        #expect(info.subjectName == "leaf.pingscape.test")
        #expect(info.subjectOrganization == nil)
        #expect(info.issuerName == "pingscape.test")
        #expect(info.issuerOrganization == "Pingscape Test Org")
        #expect(!info.isSelfIssued)
        #expect(info.serialNumber == "05")
        // 2059 is past the UTCTime range, so the certificate uses GeneralizedTime.
        #expect(info.notAfter == date(2059, 7, 30, 10, 20, 53))
        #expect(info.alternativeNames.isEmpty)
    }

    @Test func countsDaysUntilExpiry() throws {
        let info = try #require(X509.parse(der: Certificates.der(Certificates.selfSigned)))
        #expect(info.daysUntilExpiry(from: date(2036, 9, 17, 10, 20, 53)) == 1)
        #expect(info.daysUntilExpiry(from: date(2036, 9, 18, 10, 20, 52)) == 0)
        #expect(info.daysUntilExpiry(from: date(2036, 9, 19, 10, 20, 53)) == -1)
    }

    @Test func rejectsWhatIsNoCertificate() {
        #expect(X509.parse(der: []) == nil)
        #expect(X509.parse(der: [0x30, 0x03, 0x02, 0x01, 0x01]) == nil)
        #expect(X509.parse(der: Array(Certificates.der(Certificates.selfSigned).prefix(120))) == nil)
        #expect(X509.parse(der: Array("not a certificate".utf8)) == nil)
    }
}
