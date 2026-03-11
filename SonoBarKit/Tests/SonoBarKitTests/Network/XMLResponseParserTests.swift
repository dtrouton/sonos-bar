import Testing
@testable import SonoBarKit

@Suite("XMLResponseParser Tests")
struct XMLResponseParserTests {

    @Test func parseGetVolumeResponse() throws {
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
          <CurrentVolume>42</CurrentVolume>
        </u:GetVolumeResponse>
        </s:Body>
        </s:Envelope>
        """
        let result = try XMLResponseParser.parse(xml)
        #expect(result["CurrentVolume"] == "42")
    }

    @Test func parseGetTransportInfoResponse() throws {
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <CurrentTransportState>PLAYING</CurrentTransportState>
          <CurrentTransportStatus>OK</CurrentTransportStatus>
          <CurrentSpeed>1</CurrentSpeed>
        </u:GetTransportInfoResponse>
        </s:Body>
        </s:Envelope>
        """
        let result = try XMLResponseParser.parse(xml)
        #expect(result["CurrentTransportState"] == "PLAYING")
        #expect(result["CurrentSpeed"] == "1")
    }

    @Test func parsePositionInfoWithMetadata() throws {
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
          <Track>1</Track>
          <TrackDuration>0:03:45</TrackDuration>
          <RelTime>0:01:23</RelTime>
        </u:GetPositionInfoResponse>
        </s:Body>
        </s:Envelope>
        """
        let result = try XMLResponseParser.parse(xml)
        #expect(result["Track"] == "1")
        #expect(result["TrackDuration"] == "0:03:45")
        #expect(result["RelTime"] == "0:01:23")
    }

    @Test func parseSoapFault() throws {
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <s:Fault>
          <faultcode>s:Client</faultcode>
          <faultstring>UPnPError</faultstring>
          <detail><UPnPError><errorCode>701</errorCode></UPnPError></detail>
        </s:Fault>
        </s:Body>
        </s:Envelope>
        """
        #expect(throws: SOAPError.self) {
            try XMLResponseParser.parse(xml)
        }
        do {
            _ = try XMLResponseParser.parse(xml)
        } catch let soapError as SOAPError {
            #expect(soapError.code == 701)
        } catch {
            Issue.record("Expected SOAPError, got \(error)")
        }
    }

    @Test func parseHTMLEncodedLastChangeEvent() throws {
        let xml = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
        <e:property>
        <LastChange>&lt;Event&gt;&lt;InstanceID val=&quot;0&quot;&gt;&lt;TransportState val=&quot;PLAYING&quot;/&gt;&lt;/InstanceID&gt;&lt;/Event&gt;</LastChange>
        </e:property>
        </e:propertyset>
        """
        let result = try XMLResponseParser.parseEventBody(xml)
        #expect(result["TransportState"] == "PLAYING")
    }
}
