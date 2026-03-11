import Testing
@testable import SonoBarKit

@Suite("SSDPParser Tests")
struct SSDPParserTests {

    @Test func testParseValidSSDPResponse() throws {
        let response = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        LOCATION: http://192.168.1.42:1400/xml/device_description.xml\r
        SERVER: Linux UPnP/1.0 Sonos/63.2-88230 (ZPS9)\r
        ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
        USN: uuid:RINCON_48A6B88A7E4E01400::urn:schemas-upnp-org:device:ZonePlayer:1\r
        X-RINCON-HOUSEHOLD: Sonos_ABC123DEF456\r
        \r\n
        """
        let result = try #require(SSDPResponseParser.parse(response))
        #expect(result.location == "http://192.168.1.42:1400/xml/device_description.xml")
        #expect(result.uuid == "RINCON_48A6B88A7E4E01400")
        #expect(result.ip == "192.168.1.42")
        #expect(result.householdID == "Sonos_ABC123DEF456")
    }

    @Test func testParseRejectsNonSonosDevice() throws {
        let response = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        LOCATION: http://192.168.1.99:1900/rootDesc.xml\r
        SERVER: Linux UPnP/1.0 Philips-hue/1.0\r
        ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
        USN: uuid:some-other-device::urn:schemas-upnp-org:device:ZonePlayer:1\r
        \r\n
        """
        let result = SSDPResponseParser.parse(response)
        #expect(result == nil)
    }

    @Test func testParseMSearchMessage() {
        let message = SSDPDiscovery.mSearchMessage
        #expect(message.contains("M-SEARCH * HTTP/1.1\r\n"))
        #expect(message.contains("HOST: 239.255.255.250:1900\r\n"))
        #expect(message.contains("MAN: \"ssdp:discover\"\r\n"))
        #expect(message.contains("MX: 1\r\n"))
        #expect(message.contains("ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n"))
        #expect(message.hasSuffix("\r\n\r\n"))
    }

    @Test func testParseResponseMissingLocation() throws {
        let response = """
        HTTP/1.1 200 OK\r
        SERVER: Linux UPnP/1.0 Sonos/63.2-88230 (ZPS9)\r
        USN: uuid:RINCON_48A6B88A7E4E01400::urn:schemas-upnp-org:device:ZonePlayer:1\r
        \r\n
        """
        let result = SSDPResponseParser.parse(response)
        #expect(result == nil)
    }

    @Test func testParseResponseMissingUSN() throws {
        let response = """
        HTTP/1.1 200 OK\r
        LOCATION: http://192.168.1.42:1400/xml/device_description.xml\r
        SERVER: Linux UPnP/1.0 Sonos/63.2-88230 (ZPS9)\r
        \r\n
        """
        let result = SSDPResponseParser.parse(response)
        #expect(result == nil)
    }

    @Test func testParseValidResponseWithoutHouseholdID() throws {
        let response = """
        HTTP/1.1 200 OK\r
        LOCATION: http://192.168.1.42:1400/xml/device_description.xml\r
        SERVER: Linux UPnP/1.0 Sonos/63.2-88230 (ZPS9)\r
        USN: uuid:RINCON_48A6B88A7E4E01400::urn:schemas-upnp-org:device:ZonePlayer:1\r
        \r\n
        """
        let result = try #require(SSDPResponseParser.parse(response))
        #expect(result.uuid == "RINCON_48A6B88A7E4E01400")
        #expect(result.ip == "192.168.1.42")
        #expect(result.householdID == nil)
    }
}
