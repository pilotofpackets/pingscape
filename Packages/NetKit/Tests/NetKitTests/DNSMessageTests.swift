import Foundation
import Testing

@testable import NetKit

@Suite("DNS messages")
struct DNSMessageTests {
    @Test func buildsAQueryWithEDNS() throws {
        let packet = try DNSMessage.query(id: 0x1234, name: "example.com", type: .a, ednsUDPSize: 1232)
        // The recorded query of the fixtures, byte for byte.
        let expected = DNSFixtures.bytes(
            "12340100000100000000000107" + "6578616d706c6503636f6d0000010001" + "00002904d0000000000000")
        #expect(packet == expected)
    }

    @Test func buildsAQueryWithoutEDNS() throws {
        let packet = try DNSMessage.query(id: 0x1234, name: "example.com", type: .a)
        #expect(packet == DNSFixtures.bytes("123401000001000000000000076578616d706c6503636f6d0000010001"))
    }

    @Test func rejectsNamesThatDoNotFit() {
        #expect(throws: DNSError.invalidName) { try DNSMessage.encodeName(String(repeating: "a", count: 64) + ".com") }
        #expect(throws: DNSError.invalidName) { try DNSMessage.encodeName("a..com") }
        #expect(throws: DNSError.invalidName) {
            try DNSMessage.encodeName(Array(repeating: String(repeating: "a", count: 60), count: 5).joined(separator: "."))
        }
        #expect((try? DNSMessage.encodeName("")) == [0])
    }

    @Test func buildsReverseNames() {
        #expect(DNSMessage.reverseName(of: "192.0.2.42") == "42.2.0.192.in-addr.arpa")
        #expect(
            DNSMessage.reverseName(of: "2001:db8::1")
                == "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa")
        #expect(DNSMessage.reverseName(of: "example.com") == nil)
    }

    @Test func readsAnAAnswer() throws {
        let message = try DNSMessage.parse(DNSFixtures.aExample)
        #expect(message.responseCode == 0)
        #expect(message.identifier == 0x1234)
        #expect(message.hasEDNS)
        #expect(!message.isTruncated && !message.isIncomplete)
        #expect(message.answers.map(\.value) == ["104.20.23.154", "172.66.147.243"])
        #expect(message.answers.allSatisfy { $0.name == "example.com" && $0.type == "A" && $0.ttl == 87 })
    }

    @Test func readsAAAAAsCanonicalText() throws {
        let message = try DNSMessage.parse(DNSFixtures.aaaaExample)
        #expect(message.answers.map(\.value) == ["2606:4700:10::ac42:93f3", "2606:4700:10::6814:179a"])
    }

    @Test func followsNameCompressionInMXAnswers() throws {
        let message = try DNSMessage.parse(DNSFixtures.mxGmail)
        #expect(message.answers.count == 5)
        #expect(
            Set(message.answers.map(\.value))
                == [
                    "30 alt3.gmail-smtp-in.l.google.com", "20 alt2.gmail-smtp-in.l.google.com",
                    "5 gmail-smtp-in.l.google.com", "40 alt4.gmail-smtp-in.l.google.com",
                    "10 alt1.gmail-smtp-in.l.google.com",
                ])
    }

    @Test func readsTXTSOACAASRVCNAMEAndPTR() throws {
        let txt = try DNSMessage.parse(DNSFixtures.txtExample).answers
        #expect(!txt.isEmpty && txt.allSatisfy { $0.type == "TXT" && $0.value.hasPrefix("\"") && $0.value.hasSuffix("\"") })

        let soa = try #require(try DNSMessage.parse(DNSFixtures.soaExample).answers.first)
        #expect(soa.type == "SOA")
        // primary, mailbox, then five numbers.
        #expect(soa.value.split(separator: " ").count == 7)

        let caa = try DNSMessage.parse(DNSFixtures.caaGoogle).answers
        #expect(caa.contains { $0.value.hasPrefix("0 issue \"") })

        let srv = try #require(try DNSMessage.parse(DNSFixtures.srvXMPP).answers.first)
        #expect(srv.type == "SRV")
        #expect(srv.value.split(separator: " ").count == 4)
        #expect(srv.value.hasSuffix("jabber.org"))

        let cname = try DNSMessage.parse(DNSFixtures.cnameGitHub).answers
        #expect(cname.first?.type == "CNAME")
        #expect(cname.first?.value == "github.com")

        let ptr = try DNSMessage.parse(DNSFixtures.ptrCloudflare).answers
        #expect(ptr.first?.type == "PTR")
        #expect(ptr.first?.name == "1.1.1.1.in-addr.arpa")
        #expect(ptr.first?.value == "one.one.one.one")
    }

    @Test func readsNoErrorWithoutAnswersAndNXDOMAIN() throws {
        let missing = try DNSMessage.parse(DNSFixtures.nxdomain)
        #expect(missing.responseCode == 3)
        #expect(missing.answers.isEmpty)
        #expect(DNSResponse.codeName(3) == "NXDOMAIN")
        #expect(DNSResponse.codeName(0) == "NOERROR")
        #expect(DNSResponse.codeName(9) == "RCODE9")
    }

    @Test func answersWithoutEDNSCarryNoOPTRecord() throws {
        let message = try DNSMessage.parse(DNSFixtures.aExampleWithoutEDNS)
        #expect(!message.hasEDNS)
        #expect(message.answers.count == 2)
    }

    @Test func flagsAreNamed() throws {
        let message = try DNSMessage.parse(DNSFixtures.aExample)
        // 0x8180: response, recursion desired and available.
        #expect(DNSResponse.flagNames(message.flags) == ["RD", "RA"])
    }

    @Test func marksACutOffPacketAsIncomplete() throws {
        // The header promises two answers, the packet ends in the middle of the second.
        let cut = Array(DNSFixtures.aExample.prefix(DNSFixtures.aExample.count - 20))
        let message = try DNSMessage.parse(cut)
        #expect(message.isIncomplete)
        #expect(message.answers.count == 1)
        #expect(DNSClient.needsTCP(message, replyBytes: cut.count, askedWithEDNS: true))
    }

    @Test func decidesWhenTCPIsNeeded() throws {
        let complete = try DNSMessage.parse(DNSFixtures.aExample)
        #expect(!DNSClient.needsTCP(complete, replyBytes: 72, askedWithEDNS: true))

        var truncated = complete
        truncated.flags |= 0x0200
        #expect(DNSClient.needsTCP(truncated, replyBytes: 72, askedWithEDNS: true))

        // No OPT in the answer although we sent one: confirm anything sizeable.
        let stripped = try DNSMessage.parse(DNSFixtures.aExampleWithoutEDNS)
        #expect(!DNSClient.needsTCP(stripped, replyBytes: 61, askedWithEDNS: true))
        #expect(DNSClient.needsTCP(stripped, replyBytes: 300, askedWithEDNS: true))
        #expect(!DNSClient.needsTCP(stripped, replyBytes: 300, askedWithEDNS: false))
    }

    @Test func rejectsGarbage() {
        #expect(throws: DNSError.malformed) { try DNSMessage.parse([1, 2, 3]) }
    }

    @Test func stopsAtCompressionLoops() {
        // A name that points at itself.
        var packet = DNSFixtures.bytes("123481800001000100000000")
        packet += [0xC0, 12, 0, 1, 0, 1]
        packet += [0xC0, 12, 0, 1, 0, 1, 0, 0, 0, 1, 0, 4, 1, 2, 3, 4]
        let message = try? DNSMessage.parse(packet)
        #expect(message?.isIncomplete == true)
    }

    @Test func escapesUnusualBytesInNames() throws {
        var data: [UInt8] = [3, 0x61, 0x2E, 0x62, 0]  // label "a.b" with a dot inside
        #expect(try DNSMessage.readName(data, 0).name == "a\\.b")
        data = [2, 0x01, 0x7F, 0]
        #expect(try DNSMessage.readName(data, 0).name == "\\001\\127")
        #expect(try DNSMessage.readName([0], 0).name == ".")
    }
}
