import Testing
@testable import SonoBarKit

@Suite("SOAPEnvelope Tests")
struct SOAPEnvelopeTests {

    @Test func buildPlayEnvelope() throws {
        let xml = SOAPEnvelope.build(
            service: .avTransport,
            action: "Play",
            params: ["InstanceID": "0", "Speed": "1"]
        )
        #expect(xml.contains("urn:schemas-upnp-org:service:AVTransport:1"))
        #expect(xml.contains("<InstanceID>0</InstanceID>"))
        #expect(xml.contains("<Speed>1</Speed>"))
        #expect(xml.contains("<s:Envelope"))
        #expect(xml.contains("<u:Play"))
    }

    @Test func buildSetVolumeEnvelope() throws {
        let xml = SOAPEnvelope.build(
            service: .renderingControl,
            action: "SetVolume",
            params: ["InstanceID": "0", "Channel": "Master", "DesiredVolume": "42"]
        )
        #expect(xml.contains("urn:schemas-upnp-org:service:RenderingControl:1"))
        #expect(xml.contains("<DesiredVolume>42</DesiredVolume>"))
    }

    @Test func soapActionHeader() {
        let header = SOAPEnvelope.soapActionHeader(service: .avTransport, action: "Play")
        #expect(header == "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"")
    }

    @Test func allServicesHaveControlURLs() {
        for service in SonosService.allCases {
            #expect(!service.controlURL.isEmpty, "\(service) missing controlURL")
            #expect(!service.serviceType.isEmpty, "\(service) missing serviceType")
        }
    }
}
