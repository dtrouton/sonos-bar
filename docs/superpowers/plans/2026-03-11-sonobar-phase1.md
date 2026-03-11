# SonoBar Phase 1 (MVP) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that discovers Sonos speakers on the LAN and provides playback control, volume, room switching, and grouping.

**Architecture:** Swift Package (SonoBarKit) for all networking, models, and services — testable with `swift test`. Separate Xcode app target (SonoBar) for the menu bar UI shell. Communication via local UPnP/SOAP on port 1400.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSStatusItem/NSPopover), Network.framework, Foundation XMLParser, async/await concurrency.

**Spec:** `docs/superpowers/specs/2026-03-11-sonobar-design.md`

---

## Chunk 1: Project Setup + Network Layer

### Task 1: Project Scaffolding

**Files:**
- Create: `SonoBarKit/Package.swift`
- Create: `SonoBarKit/Sources/SonoBarKit/SonoBarKit.swift`
- Create: `SonoBarKit/Tests/SonoBarKitTests/SonoBarKitTests.swift`

- [ ] **Step 1: Create the Swift Package**

```bash
cd /Users/denver/src/sonos
mkdir -p SonoBarKit
cd SonoBarKit
swift package init --name SonoBarKit --type library
```

- [ ] **Step 2: Configure Package.swift for macOS 14+**

Replace `Package.swift` contents:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SonoBarKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SonoBarKit", targets: ["SonoBarKit"]),
    ],
    targets: [
        .target(name: "SonoBarKit"),
        .testTarget(name: "SonoBarKitTests", dependencies: ["SonoBarKit"]),
    ]
)
```

- [ ] **Step 3: Create source directory structure**

```bash
cd /Users/denver/src/sonos/SonoBarKit && mkdir -p Sources/SonoBarKit/{Network,Models,Services}
cd /Users/denver/src/sonos/SonoBarKit && mkdir -p Tests/SonoBarKitTests/{Network,Models,Services}
```

- [ ] **Step 4: Verify it builds**

```bash
swift build
```

Expected: Build Succeeded

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/
git commit -m "feat: scaffold SonoBarKit Swift Package"
```

---

### Task 2: SOAP Envelope Builder + Service Definitions

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Network/SonosService.swift`
- Create: `SonoBarKit/Sources/SonoBarKit/Network/SOAPEnvelope.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Network/SOAPEnvelopeTests.swift`

- [ ] **Step 1: Write the failing test for SOAP envelope XML generation**

```swift
// Tests/SonoBarKitTests/Network/SOAPEnvelopeTests.swift
import XCTest
@testable import SonoBarKit

final class SOAPEnvelopeTests: XCTestCase {
    func testBuildPlayEnvelope() throws {
        let xml = SOAPEnvelope.build(
            service: .avTransport,
            action: "Play",
            params: ["InstanceID": "0", "Speed": "1"]
        )
        XCTAssertTrue(xml.contains("urn:schemas-upnp-org:service:AVTransport:1"))
        XCTAssertTrue(xml.contains("<InstanceID>0</InstanceID>"))
        XCTAssertTrue(xml.contains("<Speed>1</Speed>"))
        XCTAssertTrue(xml.contains("<s:Envelope"))
        XCTAssertTrue(xml.contains("<u:Play"))
    }

    func testBuildSetVolumeEnvelope() throws {
        let xml = SOAPEnvelope.build(
            service: .renderingControl,
            action: "SetVolume",
            params: ["InstanceID": "0", "Channel": "Master", "DesiredVolume": "42"]
        )
        XCTAssertTrue(xml.contains("urn:schemas-upnp-org:service:RenderingControl:1"))
        XCTAssertTrue(xml.contains("<DesiredVolume>42</DesiredVolume>"))
    }

    func testSoapActionHeader() {
        let header = SOAPEnvelope.soapActionHeader(service: .avTransport, action: "Play")
        XCTAssertEqual(header, "\"urn:schemas-upnp-org:service:AVTransport:1#Play\"")
    }

    func testAllServicesHaveControlURLs() {
        for service in SonosService.allCases {
            XCTAssertFalse(service.controlURL.isEmpty, "\(service) missing controlURL")
            XCTAssertFalse(service.serviceType.isEmpty, "\(service) missing serviceType")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/denver/src/sonos/SonoBarKit
swift test --filter SOAPEnvelopeTests 2>&1 | tail -5
```

Expected: compilation error — types not defined yet.

- [ ] **Step 3: Implement SonosService enum**

```swift
// Sources/SonoBarKit/Network/SonosService.swift

/// Defines all Sonos UPnP services with their control URLs, event URLs, and service types.
public enum SonosService: String, CaseIterable, Sendable {
    case avTransport
    case renderingControl
    case groupRenderingControl
    case zoneGroupTopology
    case contentDirectory
    case alarmClock
    case deviceProperties

    public var controlURL: String {
        switch self {
        case .avTransport:            return "/MediaRenderer/AVTransport/Control"
        case .renderingControl:       return "/MediaRenderer/RenderingControl/Control"
        case .groupRenderingControl:  return "/MediaRenderer/GroupRenderingControl/Control"
        case .zoneGroupTopology:      return "/ZoneGroupTopology/Control"
        case .contentDirectory:       return "/MediaServer/ContentDirectory/Control"
        case .alarmClock:             return "/AlarmClock/Control"
        case .deviceProperties:       return "/DeviceProperties/Control"
        }
    }

    public var eventURL: String {
        switch self {
        case .avTransport:            return "/MediaRenderer/AVTransport/Event"
        case .renderingControl:       return "/MediaRenderer/RenderingControl/Event"
        case .groupRenderingControl:  return "/MediaRenderer/GroupRenderingControl/Event"
        case .zoneGroupTopology:      return "/ZoneGroupTopology/Event"
        case .contentDirectory:       return "/MediaServer/ContentDirectory/Event"
        case .alarmClock:             return "/AlarmClock/Event"
        case .deviceProperties:       return "/DeviceProperties/Event"
        }
    }

    public var serviceType: String {
        let name: String
        switch self {
        case .avTransport:            name = "AVTransport"
        case .renderingControl:       name = "RenderingControl"
        case .groupRenderingControl:  name = "GroupRenderingControl"
        case .zoneGroupTopology:      name = "ZoneGroupTopology"
        case .contentDirectory:       name = "ContentDirectory"
        case .alarmClock:             name = "AlarmClock"
        case .deviceProperties:       name = "DeviceProperties"
        }
        return "urn:schemas-upnp-org:service:\(name):1"
    }
}
```

- [ ] **Step 4: Implement SOAPEnvelope builder**

```swift
// Sources/SonoBarKit/Network/SOAPEnvelope.swift

/// Builds SOAP XML envelopes and headers for Sonos UPnP requests.
public enum SOAPEnvelope {
    /// Builds a complete SOAP XML envelope for a Sonos action.
    public static func build(
        service: SonosService,
        action: String,
        params: [(String, String)] = []
    ) -> String {
        let paramXML = params.map { "<\($0.0)>\($0.1)</\($0.0)>" }.joined(separator: "\n  ")
        return """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
        <u:\(action) xmlns:u="\(service.serviceType)">
          \(paramXML)
        </u:\(action)>
        </s:Body>
        </s:Envelope>
        """
    }

    /// Overload accepting a dictionary (unordered — use array of tuples if order matters).
    public static func build(
        service: SonosService,
        action: String,
        params: [String: String]
    ) -> String {
        build(service: service, action: action, params: params.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    }

    /// Returns the SOAPACTION header value for a given service and action.
    public static func soapActionHeader(service: SonosService, action: String) -> String {
        "\"\(service.serviceType)#\(action)\""
    }
}
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter SOAPEnvelopeTests
```

Expected: All 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Network/ SonoBarKit/Tests/
git commit -m "feat: add SOAP envelope builder and Sonos service definitions"
```

---

### Task 3: XML Response Parser

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Network/XMLResponseParser.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Network/XMLResponseParserTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SonoBarKitTests/Network/XMLResponseParserTests.swift
import XCTest
@testable import SonoBarKit

final class XMLResponseParserTests: XCTestCase {
    func testParseGetVolumeResponse() throws {
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
        XCTAssertEqual(result["CurrentVolume"], "42")
    }

    func testParseGetTransportInfoResponse() throws {
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
        XCTAssertEqual(result["CurrentTransportState"], "PLAYING")
        XCTAssertEqual(result["CurrentSpeed"], "1")
    }

    func testParsePositionInfoWithMetadata() throws {
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
        XCTAssertEqual(result["Track"], "1")
        XCTAssertEqual(result["TrackDuration"], "0:03:45")
        XCTAssertEqual(result["RelTime"], "0:01:23")
    }

    func testParseSoapFault() throws {
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
        XCTAssertThrowsError(try XMLResponseParser.parse(xml)) { error in
            guard let soapError = error as? SOAPError else {
                XCTFail("Expected SOAPError"); return
            }
            XCTAssertEqual(soapError.code, 701)
        }
    }

    func testParseHTMLEncodedLastChangeEvent() throws {
        let xml = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
        <e:property>
        <LastChange>&lt;Event&gt;&lt;InstanceID val=&quot;0&quot;&gt;&lt;TransportState val=&quot;PLAYING&quot;/&gt;&lt;/InstanceID&gt;&lt;/Event&gt;</LastChange>
        </e:property>
        </e:propertyset>
        """
        let result = try XMLResponseParser.parseEventBody(xml)
        XCTAssertEqual(result["TransportState"], "PLAYING")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter XMLResponseParserTests 2>&1 | tail -5
```

Expected: compilation error.

- [ ] **Step 3: Implement XMLResponseParser**

```swift
// Sources/SonoBarKit/Network/XMLResponseParser.swift
import Foundation

/// Error from a SOAP fault response.
public struct SOAPError: Error, Sendable {
    public let code: Int
    public let description: String

    public init(code: Int, description: String = "") {
        self.code = code
        self.description = description
    }
}

/// Parses SOAP XML responses from Sonos speakers into key-value dictionaries.
public enum XMLResponseParser {
    /// Parses a SOAP response envelope, returning the child elements of the action response.
    /// Throws SOAPError if the response contains a SOAP fault.
    public static func parse(_ xml: String) throws -> [String: String] {
        let data = Data(xml.utf8)
        let delegate = SOAPResponseDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        if let fault = delegate.fault {
            throw fault
        }
        return delegate.values
    }

    /// Parses a UPnP event notification body.
    /// Handles the HTML-encoded LastChange element by unescaping and re-parsing.
    public static func parseEventBody(_ xml: String) throws -> [String: String] {
        let data = Data(xml.utf8)
        let delegate = EventPropertyDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        // LastChange contains HTML-encoded XML — unescape and parse the inner XML
        guard let lastChange = delegate.values["LastChange"] else {
            return delegate.values
        }
        let unescaped = lastChange
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")

        let innerDelegate = LastChangeDelegate()
        let innerParser = XMLParser(data: Data(unescaped.utf8))
        innerParser.delegate = innerDelegate
        innerParser.parse()
        return innerDelegate.values
    }
}

// MARK: - XMLParser Delegates

private final class SOAPResponseDelegate: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    var fault: SOAPError?
    private var currentElement = ""
    private var currentText = ""
    private var inBody = false
    private var inFault = false
    private var depth = 0
    private var responseDepth = -1
    private var faultCode = 0

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        depth += 1
        let local = element.components(separatedBy: ":").last ?? element
        currentElement = local
        currentText = ""
        if local == "Body" { inBody = true }
        if local == "Fault" { inFault = true }
        if inBody && !inFault && local.hasSuffix("Response") { responseDepth = depth }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        let local = element.components(separatedBy: ":").last ?? element
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if responseDepth > 0 && depth == responseDepth + 1 && !trimmed.isEmpty {
            values[local] = trimmed
        }
        if inFault && local == "errorCode" {
            faultCode = Int(trimmed) ?? 0
        }
        if local == "Fault" {
            fault = SOAPError(code: faultCode)
            inFault = false
        }
        if local.hasSuffix("Response") && depth == responseDepth { responseDepth = -1 }
        depth -= 1
    }
}

private final class EventPropertyDelegate: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    private var currentElement = ""
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let local = element.components(separatedBy: ":").last ?? element
        currentElement = local
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        let local = element.components(separatedBy: ":").last ?? element
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            values[local] = trimmed
        }
    }
}

private final class LastChangeDelegate: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        // LastChange inner XML uses val attributes: <TransportState val="PLAYING"/>
        if let val = attributes["val"], element != "InstanceID" && element != "Event" {
            values[element] = val
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter XMLResponseParserTests
```

Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/ SonoBarKit/Tests/
git commit -m "feat: add XML response parser for SOAP and UPnP events"
```

---

### Task 4: SOAP Client (HTTP Layer)

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Network/SOAPClient.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Network/SOAPClientTests.swift`

- [ ] **Step 1: Write the failing tests using a protocol-based mock**

```swift
// Tests/SonoBarKitTests/Network/SOAPClientTests.swift
import XCTest
@testable import SonoBarKit

final class SOAPClientTests: XCTestCase {
    func testCallActionBuildsCorrectRequest() async throws {
        let mock = MockHTTPClient()
        mock.responseBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
          <CurrentVolume>55</CurrentVolume>
        </u:GetVolumeResponse>
        </s:Body>
        </s:Envelope>
        """
        let client = SOAPClient(host: "192.168.1.50", httpClient: mock)
        let result = try await client.callAction(
            service: .renderingControl,
            action: "GetVolume",
            params: ["InstanceID": "0", "Channel": "Master"]
        )
        XCTAssertEqual(result["CurrentVolume"], "55")

        // Verify the request was well-formed
        let req = try XCTUnwrap(mock.lastRequest)
        XCTAssertEqual(req.url?.path, "/MediaRenderer/RenderingControl/Control")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertTrue(req.value(forHTTPHeaderField: "SOAPACTION")?.contains("GetVolume") ?? false)
    }

    func testCallActionThrowsOnSOAPFault() async {
        let mock = MockHTTPClient()
        mock.responseBody = """
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
        let client = SOAPClient(host: "192.168.1.50", httpClient: mock)
        do {
            _ = try await client.callAction(service: .avTransport, action: "Play", params: [:])
            XCTFail("Should have thrown")
        } catch let error as SOAPError {
            XCTAssertEqual(error.code, 701)
        }
    }
}

// MARK: - Mock

final class MockHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    var responseBody = ""
    var statusCode = 200
    var lastRequest: URLRequest?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let data = Data(responseBody.utf8)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode,
            httpVersion: nil, headerFields: nil
        )!
        return (data, response)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter SOAPClientTests 2>&1 | tail -5
```

Expected: compilation error.

- [ ] **Step 3: Implement SOAPClient with protocol-based HTTP**

```swift
// Sources/SonoBarKit/Network/SOAPClient.swift
import Foundation

/// Protocol for HTTP transport, enabling test mocking.
public protocol HTTPClientProtocol: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Default HTTP client using URLSession.
public struct URLSessionHTTPClient: HTTPClientProtocol {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}

/// Sends SOAP requests to a Sonos speaker and parses responses.
public final class SOAPClient: Sendable {
    public let host: String
    public let port: Int
    private let httpClient: HTTPClientProtocol

    public init(host: String, port: Int = 1400, httpClient: HTTPClientProtocol? = nil) {
        self.host = host
        self.port = port
        self.httpClient = httpClient ?? URLSessionHTTPClient()
    }

    /// Calls a SOAP action on the speaker and returns the parsed response values.
    public func callAction(
        service: SonosService,
        action: String,
        params: [String: String]
    ) async throws -> [String: String] {
        let body = SOAPEnvelope.build(service: service, action: action, params: params)
        let url = URL(string: "http://\(host):\(port)\(service.controlURL)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(
            SOAPEnvelope.soapActionHeader(service: service, action: action),
            forHTTPHeaderField: "SOAPACTION"
        )
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = 5

        let (data, _) = try await httpClient.send(request)
        let xml = String(data: data, encoding: .utf8) ?? ""
        return try XMLResponseParser.parse(xml)
    }

    /// Calls a SOAP action with ordered parameters (tuple array).
    /// Use this overload when parameter order matters (e.g., SetAVTransportURI).
    public func callAction(
        service: SonosService,
        action: String,
        params: [(String, String)]
    ) async throws -> [String: String] {
        let body = SOAPEnvelope.build(service: service, action: action, params: params)
        let url = URL(string: "http://\(host):\(port)\(service.controlURL)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(
            SOAPEnvelope.soapActionHeader(service: service, action: action),
            forHTTPHeaderField: "SOAPACTION"
        )
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = 5

        let (data, _) = try await httpClient.send(request)
        let xml = String(data: data, encoding: .utf8) ?? ""
        return try XMLResponseParser.parse(xml)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter SOAPClientTests
```

Expected: All 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/ SonoBarKit/Tests/
git commit -m "feat: add SOAP client with protocol-based HTTP for testability"
```

---

### Task 5: SSDP Discovery

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Network/SSDPDiscovery.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Network/SSDPParserTests.swift`

- [ ] **Step 1: Write the failing tests for SSDP response parsing**

Note: We test the _parsing_ of SSDP responses (pure logic), not the UDP networking (requires real network).

```swift
// Tests/SonoBarKitTests/Network/SSDPParserTests.swift
import XCTest
@testable import SonoBarKit

final class SSDPParserTests: XCTestCase {
    func testParseValidSSDPResponse() throws {
        let response = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age = 1800\r
        LOCATION: http://192.168.1.50:1400/xml/device_description.xml\r
        SERVER: Linux UPnP/1.0 Sonos/72.0-12345 (ZPS9)\r
        ST: urn:schemas-upnp-org:device:ZonePlayer:1\r
        USN: uuid:RINCON_B8E9378E621401400::urn:schemas-upnp-org:device:ZonePlayer:1\r
        X-RINCON-HOUSEHOLD: Sonos_abc123\r
        \r
        """
        let result = try XCTUnwrap(SSDPResponseParser.parse(response))
        XCTAssertEqual(result.location, "http://192.168.1.50:1400/xml/device_description.xml")
        XCTAssertEqual(result.uuid, "RINCON_B8E9378E621401400")
        XCTAssertEqual(result.ip, "192.168.1.50")
        XCTAssertEqual(result.householdID, "Sonos_abc123")
    }

    func testParseRejectsNonSonosDevice() {
        let response = """
        HTTP/1.1 200 OK\r
        LOCATION: http://192.168.1.99:8080/desc.xml\r
        SERVER: Linux UPnP/1.0 SomeOtherDevice/1.0\r
        USN: uuid:other-device\r
        \r
        """
        XCTAssertNil(SSDPResponseParser.parse(response))
    }

    func testParseMSearchMessage() {
        let msg = SSDPDiscovery.mSearchMessage
        XCTAssertTrue(msg.contains("M-SEARCH * HTTP/1.1"))
        XCTAssertTrue(msg.contains("239.255.255.250:1900"))
        XCTAssertTrue(msg.contains("ZonePlayer:1"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter SSDPParserTests 2>&1 | tail -5
```

- [ ] **Step 3: Implement SSDPDiscovery and SSDPResponseParser**

```swift
// Sources/SonoBarKit/Network/SSDPDiscovery.swift
import Foundation
import Network

/// Result of parsing one SSDP response.
public struct SSDPResult: Sendable, Equatable {
    public let location: String
    public let uuid: String
    public let ip: String
    public let householdID: String?
}

/// Parses SSDP HTTP response strings.
public enum SSDPResponseParser {
    /// Parses an SSDP response string. Returns nil if it's not a Sonos device.
    public static func parse(_ response: String) -> SSDPResult? {
        var headers: [String: String] = [:]
        for line in response.components(separatedBy: "\r\n") {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        // Reject non-Sonos devices
        guard let server = headers["SERVER"], server.contains("Sonos") else { return nil }
        guard let location = headers["LOCATION"] else { return nil }
        guard let usn = headers["USN"] else { return nil }

        // Extract UUID from USN: "uuid:RINCON_xxx::urn:..."
        let uuid: String
        if let uuidStart = usn.range(of: "uuid:")?.upperBound {
            let rest = usn[uuidStart...]
            if let colonRange = rest.range(of: "::") {
                uuid = String(rest[..<colonRange.lowerBound])
            } else {
                uuid = String(rest)
            }
        } else {
            return nil
        }

        // Extract IP from location URL
        guard let url = URL(string: location), let host = url.host else { return nil }

        return SSDPResult(
            location: location,
            uuid: uuid,
            ip: host,
            householdID: headers["X-RINCON-HOUSEHOLD"]
        )
    }
}

/// Discovers Sonos speakers on the local network via SSDP multicast.
public final class SSDPDiscovery: Sendable {
    public static let multicastAddress = "239.255.255.250"
    public static let multicastPort: UInt16 = 1900

    public static var mSearchMessage: String {
        "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"
    }

    /// Performs a single SSDP discovery scan. Returns discovered speakers.
    /// Uses BSD sockets for UDP multicast (most reliable for SSDP M-SEARCH).
    public func scan(timeout: TimeInterval = 3) async -> [SSDPResult] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var results: [SSDPResult] = []
                let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard fd >= 0 else {
                    continuation.resume(returning: [])
                    return
                }
                defer { close(fd) }

                // Set receive timeout
                var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                // Send M-SEARCH to multicast address
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = Self.multicastPort.bigEndian
                inet_pton(AF_INET, Self.multicastAddress, &addr.sin_addr)

                let msg = Data(Self.mSearchMessage.utf8)
                msg.withUnsafeBytes { ptr in
                    withUnsafePointer(to: &addr) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            sendto(fd, ptr.baseAddress, msg.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }

                // Receive responses until timeout
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let n = recv(fd, &buffer, buffer.count, 0)
                    guard n > 0 else { break }
                    if let response = String(bytes: buffer[..<n], encoding: .utf8),
                       let result = SSDPResponseParser.parse(response),
                       !results.contains(where: { $0.uuid == result.uuid }) {
                        results.append(result)
                    }
                }

                continuation.resume(returning: results)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter SSDPParserTests
```

Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/ SonoBarKit/Tests/
git commit -m "feat: add SSDP discovery with response parser"
```

---

### Task 6: UPnP Event Listener

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Network/UPnPEventListener.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Network/UPnPEventListenerTests.swift`

- [ ] **Step 1: Write failing tests for subscription request building and event parsing**

```swift
// Tests/SonoBarKitTests/Network/UPnPEventListenerTests.swift
import XCTest
@testable import SonoBarKit

final class UPnPEventListenerTests: XCTestCase {
    func testBuildSubscribeRequest() throws {
        let req = UPnPSubscription.buildSubscribeRequest(
            speakerHost: "192.168.1.50",
            service: .avTransport,
            callbackURL: "http://192.168.1.100:54321"
        )
        XCTAssertEqual(req.httpMethod, "SUBSCRIBE")
        XCTAssertEqual(req.url?.path, "/MediaRenderer/AVTransport/Event")
        XCTAssertEqual(req.value(forHTTPHeaderField: "NT"), "upnp:event")
        XCTAssertEqual(req.value(forHTTPHeaderField: "CALLBACK"), "<http://192.168.1.100:54321>")
        XCTAssertTrue(req.value(forHTTPHeaderField: "TIMEOUT")?.hasPrefix("Second-") ?? false)
    }

    func testBuildRenewRequest() throws {
        let req = UPnPSubscription.buildRenewRequest(
            speakerHost: "192.168.1.50",
            service: .avTransport,
            sid: "uuid:RINCON_xxx_sub123"
        )
        XCTAssertEqual(req.httpMethod, "SUBSCRIBE")
        XCTAssertEqual(req.value(forHTTPHeaderField: "SID"), "uuid:RINCON_xxx_sub123")
        XCTAssertNil(req.value(forHTTPHeaderField: "CALLBACK"))
        XCTAssertNil(req.value(forHTTPHeaderField: "NT"))
    }

    func testBuildUnsubscribeRequest() throws {
        let req = UPnPSubscription.buildUnsubscribeRequest(
            speakerHost: "192.168.1.50",
            service: .avTransport,
            sid: "uuid:RINCON_xxx_sub123"
        )
        XCTAssertEqual(req.httpMethod, "UNSUBSCRIBE")
        XCTAssertEqual(req.value(forHTTPHeaderField: "SID"), "uuid:RINCON_xxx_sub123")
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter UPnPEventListenerTests 2>&1 | tail -5
```

- [ ] **Step 3: Implement UPnP subscription helpers and event listener**

```swift
// Sources/SonoBarKit/Network/UPnPEventListener.swift
import Foundation
import Network

/// Builds UPnP SUBSCRIBE/UNSUBSCRIBE requests.
public enum UPnPSubscription {
    public static let defaultTimeout = 3600

    public static func buildSubscribeRequest(
        speakerHost: String,
        service: SonosService,
        callbackURL: String,
        timeout: Int = defaultTimeout
    ) -> URLRequest {
        let url = URL(string: "http://\(speakerHost):1400\(service.eventURL)")!
        var req = URLRequest(url: url)
        req.httpMethod = "SUBSCRIBE"
        req.setValue("<\(callbackURL)>", forHTTPHeaderField: "CALLBACK")
        req.setValue("upnp:event", forHTTPHeaderField: "NT")
        req.setValue("Second-\(timeout)", forHTTPHeaderField: "TIMEOUT")
        return req
    }

    public static func buildRenewRequest(
        speakerHost: String,
        service: SonosService,
        sid: String,
        timeout: Int = defaultTimeout
    ) -> URLRequest {
        let url = URL(string: "http://\(speakerHost):1400\(service.eventURL)")!
        var req = URLRequest(url: url)
        req.httpMethod = "SUBSCRIBE"
        req.setValue(sid, forHTTPHeaderField: "SID")
        req.setValue("Second-\(timeout)", forHTTPHeaderField: "TIMEOUT")
        return req
    }

    public static func buildUnsubscribeRequest(
        speakerHost: String,
        service: SonosService,
        sid: String
    ) -> URLRequest {
        let url = URL(string: "http://\(speakerHost):1400\(service.eventURL)")!
        var req = URLRequest(url: url)
        req.httpMethod = "UNSUBSCRIBE"
        req.setValue(sid, forHTTPHeaderField: "SID")
        return req
    }
}

/// Callback type for UPnP event notifications.
public typealias EventCallback = @Sendable (SonosService, [String: String]) -> Void

/// Runs a lightweight HTTP server to receive UPnP event notifications from Sonos speakers.
/// Uses per-service callback URL paths (e.g., /event/avTransport) to identify the source service.
public final class UPnPEventListener: @unchecked Sendable {
    private var listener: NWListener?
    public private(set) var port: UInt16 = 0
    private var onEvent: EventCallback?

    /// Maps URL path suffixes to SonosService for event identification.
    private static let pathToService: [String: SonosService] = Dictionary(
        uniqueKeysWithValues: SonosService.allCases.map { ("/event/\($0.rawValue)", $0) }
    )

    /// Returns the callback URL path for a given service.
    public static func callbackPath(for service: SonosService) -> String {
        "/event/\(service.rawValue)"
    }

    public init() {}

    /// Starts the HTTP listener on a random available port.
    /// Tries up to 5 ports before giving up.
    public func start(onEvent: @escaping EventCallback) throws {
        self.onEvent = onEvent
        var lastError: Error?

        for _ in 0..<5 {
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                listener.newConnectionHandler = { [weak self] conn in
                    self?.handleConnection(conn)
                }
                let semaphore = DispatchSemaphore(value: 0)
                var started = false

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        started = true
                        semaphore.signal()
                    case .failed(let error):
                        lastError = error
                        semaphore.signal()
                    default:
                        break
                    }
                }
                listener.start(queue: .global())
                _ = semaphore.wait(timeout: .now() + 2)

                if started, let actualPort = listener.port?.rawValue {
                    self.listener = listener
                    self.port = actualPort
                    return
                }
                listener.cancel()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    /// Stops the listener and cleans up.
    public func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] content, _, _, _ in
            defer { connection.cancel() }
            guard let data = content, let body = String(data: data, encoding: .utf8) else { return }

            // Send 200 OK response
            let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
            connection.send(content: Data(response.utf8), completion: .idempotent)

            // Determine which service sent this event from the request path
            // First line: "NOTIFY /event/avTransport HTTP/1.1"
            let firstLine = body.prefix(while: { $0 != "\r" && $0 != "\n" })
            let pathComponent = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let service = Self.pathToService[pathComponent] ?? .avTransport

            // Parse the event XML from the HTTP body (after blank line)
            if let range = body.range(of: "\r\n\r\n") {
                let xmlBody = String(body[range.upperBound...])
                if let values = try? XMLResponseParser.parseEventBody(xmlBody) {
                    self?.onEvent?(service, values)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter UPnPEventListenerTests
```

Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/ SonoBarKit/Tests/
git commit -m "feat: add UPnP event listener and subscription helpers"
```

---

## Chunk 2: Models + Service Layer

### Task 7: Data Models

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Models/SonosDevice.swift`
- Create: `SonoBarKit/Sources/SonoBarKit/Models/PlaybackState.swift`
- Create: `SonoBarKit/Sources/SonoBarKit/Models/GroupTopology.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Models/ModelTests.swift`

- [ ] **Step 1: Write failing tests for model creation and zone group XML parsing**

```swift
// Tests/SonoBarKitTests/Models/ModelTests.swift
import XCTest
@testable import SonoBarKit

final class ModelTests: XCTestCase {
    func testSonosDeviceCreation() {
        let device = SonosDevice(
            uuid: "RINCON_B8E9378E621401400",
            ip: "192.168.1.50",
            roomName: "Living Room",
            modelName: "Sonos One"
        )
        XCTAssertEqual(device.uuid, "RINCON_B8E9378E621401400")
        XCTAssertEqual(device.roomName, "Living Room")
        XCTAssertTrue(device.isReachable)
    }

    func testTransportStateFromString() {
        XCTAssertEqual(TransportState(rawValue: "PLAYING"), .playing)
        XCTAssertEqual(TransportState(rawValue: "PAUSED_PLAYBACK"), .paused)
        XCTAssertEqual(TransportState(rawValue: "STOPPED"), .stopped)
        XCTAssertEqual(TransportState(rawValue: "TRANSITIONING"), .transitioning)
    }

    func testTrackInfoFromPositionResponse() {
        let response: [String: String] = [
            "Track": "3",
            "TrackDuration": "0:03:45",
            "RelTime": "0:01:23",
            "TrackURI": "x-sonos-spotify:spotify:track:abc",
            "TrackMetaData": "<item><dc:title>Midnight City</dc:title><dc:creator>M83</dc:creator><upnp:album>Hurry Up</upnp:album></item>"
        ]
        let track = TrackInfo(fromPositionInfo: response)
        XCTAssertEqual(track?.trackNumber, 3)
        XCTAssertEqual(track?.duration, "0:03:45")
        XCTAssertEqual(track?.elapsed, "0:01:23")
        XCTAssertEqual(track?.uri, "x-sonos-spotify:spotify:track:abc")
        XCTAssertEqual(track?.title, "Midnight City")
        XCTAssertEqual(track?.artist, "M83")
        XCTAssertEqual(track?.album, "Hurry Up")
    }

    func testParseZoneGroupState() throws {
        let xml = """
        <ZoneGroupState>
        <ZoneGroups>
        <ZoneGroup Coordinator="RINCON_AAA" ID="RINCON_AAA:1">
          <ZoneGroupMember UUID="RINCON_AAA" Location="http://192.168.1.50:1400/xml/device_description.xml" ZoneName="Living Room" />
          <ZoneGroupMember UUID="RINCON_BBB" Location="http://192.168.1.51:1400/xml/device_description.xml" ZoneName="Kitchen" />
        </ZoneGroup>
        <ZoneGroup Coordinator="RINCON_CCC" ID="RINCON_CCC:2">
          <ZoneGroupMember UUID="RINCON_CCC" Location="http://192.168.1.52:1400/xml/device_description.xml" ZoneName="Bedroom" />
        </ZoneGroup>
        </ZoneGroups>
        </ZoneGroupState>
        """
        let groups = try ZoneGroupParser.parse(xml)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].coordinatorUUID, "RINCON_AAA")
        XCTAssertEqual(groups[0].members.count, 2)
        XCTAssertEqual(groups[0].members[0].zoneName, "Living Room")
        XCTAssertEqual(groups[1].members.count, 1)
        XCTAssertEqual(groups[1].members[0].zoneName, "Bedroom")
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter ModelTests 2>&1 | tail -5
```

- [ ] **Step 3: Implement models**

```swift
// Sources/SonoBarKit/Models/SonosDevice.swift
import Foundation

/// Represents a Sonos speaker on the network.
public struct SonosDevice: Identifiable, Sendable, Equatable {
    public let uuid: String
    public var ip: String
    public var roomName: String
    public var modelName: String
    public var isReachable: Bool

    public var id: String { uuid }

    public init(uuid: String, ip: String, roomName: String, modelName: String = "", isReachable: Bool = true) {
        self.uuid = uuid
        self.ip = ip
        self.roomName = roomName
        self.modelName = modelName
        self.isReachable = isReachable
    }
}
```

```swift
// Sources/SonoBarKit/Models/PlaybackState.swift
import Foundation

/// Transport state of a Sonos speaker.
public enum TransportState: String, Sendable {
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
}

/// Information about the currently playing track.
public struct TrackInfo: Sendable, Equatable {
    public let trackNumber: Int
    public let duration: String
    public let elapsed: String
    public let uri: String
    public let title: String?
    public let artist: String?
    public let album: String?
    public let albumArtURI: String?

    public init?(fromPositionInfo info: [String: String]) {
        guard let trackStr = info["Track"], let num = Int(trackStr) else { return nil }
        self.trackNumber = num
        self.duration = info["TrackDuration"] ?? "0:00:00"
        self.elapsed = info["RelTime"] ?? "0:00:00"
        self.uri = info["TrackURI"] ?? ""

        // Parse metadata XML for title/artist/album if present
        let meta = info["TrackMetaData"] ?? ""
        self.title = Self.extractTag("dc:title", from: meta)
        self.artist = Self.extractTag("dc:creator", from: meta)
        self.album = Self.extractTag("upnp:album", from: meta)
        self.albumArtURI = Self.extractTag("upnp:albumArtURI", from: meta)
    }

    private static func extractTag(_ tag: String, from xml: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>")?.upperBound,
              let end = xml.range(of: "</\(tag)>")?.lowerBound,
              start < end else { return nil }
        return String(xml[start..<end])
    }
}

/// Complete playback state for a speaker/group.
public struct PlaybackState: Sendable, Equatable {
    public var transportState: TransportState
    public var volume: Int
    public var isMuted: Bool
    public var currentTrack: TrackInfo?

    public init(transportState: TransportState = .stopped, volume: Int = 0,
                isMuted: Bool = false, currentTrack: TrackInfo? = nil) {
        self.transportState = transportState
        self.volume = volume
        self.isMuted = isMuted
        self.currentTrack = currentTrack
    }
}
```

```swift
// Sources/SonoBarKit/Models/GroupTopology.swift
import Foundation

/// A member of a Sonos zone group.
public struct ZoneGroupMember: Sendable, Equatable {
    public let uuid: String
    public let location: String
    public let zoneName: String
    public let ip: String

    public init(uuid: String, location: String, zoneName: String) {
        self.uuid = uuid
        self.location = location
        self.zoneName = zoneName
        // Extract IP from location URL
        self.ip = URL(string: location)?.host ?? ""
    }
}

/// A group of Sonos speakers playing in sync.
public struct ZoneGroup: Sendable, Equatable {
    public let coordinatorUUID: String
    public let groupID: String
    public let members: [ZoneGroupMember]

    public var isStandalone: Bool { members.count == 1 }
}

/// Parses the ZoneGroupState XML from a Sonos speaker.
public enum ZoneGroupParser {
    public static func parse(_ xml: String) throws -> [ZoneGroup] {
        let delegate = ZoneGroupXMLDelegate()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? SOAPError(code: -1, description: "Failed to parse ZoneGroupState XML")
        }
        return delegate.groups
    }
}

private final class ZoneGroupXMLDelegate: NSObject, XMLParserDelegate {
    var groups: [ZoneGroup] = []
    private var currentCoordinator = ""
    private var currentGroupID = ""
    private var currentMembers: [ZoneGroupMember] = []

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if element == "ZoneGroup" {
            currentCoordinator = attributes["Coordinator"] ?? ""
            currentGroupID = attributes["ID"] ?? ""
            currentMembers = []
        } else if element == "ZoneGroupMember" {
            let member = ZoneGroupMember(
                uuid: attributes["UUID"] ?? "",
                location: attributes["Location"] ?? "",
                zoneName: attributes["ZoneName"] ?? ""
            )
            currentMembers.append(member)
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        if element == "ZoneGroup" {
            groups.append(ZoneGroup(
                coordinatorUUID: currentCoordinator,
                groupID: currentGroupID,
                members: currentMembers
            ))
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter ModelTests
```

Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/ SonoBarKit/Tests/
git commit -m "feat: add data models for devices, playback state, and zone groups"
```

---

### Task 8: DeviceManager

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/DeviceManager.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Services/DeviceManagerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/SonoBarKitTests/Services/DeviceManagerTests.swift
import XCTest
@testable import SonoBarKit

final class DeviceManagerTests: XCTestCase {
    func testUpdateDevicesFromZoneGroupState() throws {
        let manager = DeviceManager()
        let xml = """
        <ZoneGroupState>
        <ZoneGroups>
        <ZoneGroup Coordinator="RINCON_AAA" ID="RINCON_AAA:1">
          <ZoneGroupMember UUID="RINCON_AAA" Location="http://192.168.1.50:1400/xml/device_description.xml" ZoneName="Living Room" />
          <ZoneGroupMember UUID="RINCON_BBB" Location="http://192.168.1.51:1400/xml/device_description.xml" ZoneName="Kitchen" />
        </ZoneGroup>
        </ZoneGroups>
        </ZoneGroupState>
        """
        try manager.updateFromZoneGroupState(xml)
        XCTAssertEqual(manager.devices.count, 2)
        XCTAssertEqual(manager.groups.count, 1)
        XCTAssertEqual(manager.devices.first(where: { $0.uuid == "RINCON_AAA" })?.roomName, "Living Room")
    }

    func testCoordinatorForDevice() throws {
        let manager = DeviceManager()
        let xml = """
        <ZoneGroupState>
        <ZoneGroups>
        <ZoneGroup Coordinator="RINCON_AAA" ID="RINCON_AAA:1">
          <ZoneGroupMember UUID="RINCON_AAA" Location="http://192.168.1.50:1400/xml/device_description.xml" ZoneName="Living Room" />
          <ZoneGroupMember UUID="RINCON_BBB" Location="http://192.168.1.51:1400/xml/device_description.xml" ZoneName="Kitchen" />
        </ZoneGroup>
        </ZoneGroups>
        </ZoneGroupState>
        """
        try manager.updateFromZoneGroupState(xml)
        // Kitchen's coordinator should be Living Room (RINCON_AAA)
        let coordinator = manager.coordinatorIP(for: "RINCON_BBB")
        XCTAssertEqual(coordinator, "192.168.1.50")
    }

    func testActiveDevicePersistsAcrossUpdates() throws {
        let manager = DeviceManager()
        let xml = """
        <ZoneGroupState>
        <ZoneGroups>
        <ZoneGroup Coordinator="RINCON_AAA" ID="RINCON_AAA:1">
          <ZoneGroupMember UUID="RINCON_AAA" Location="http://192.168.1.50:1400/xml/device_description.xml" ZoneName="Living Room" />
        </ZoneGroup>
        </ZoneGroups>
        </ZoneGroupState>
        """
        try manager.updateFromZoneGroupState(xml)
        manager.setActiveDevice(uuid: "RINCON_AAA")
        XCTAssertEqual(manager.activeDevice?.uuid, "RINCON_AAA")

        // Update again — active device should persist
        try manager.updateFromZoneGroupState(xml)
        XCTAssertEqual(manager.activeDevice?.uuid, "RINCON_AAA")
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter DeviceManagerTests 2>&1 | tail -5
```

- [ ] **Step 3: Implement DeviceManager**

```swift
// Sources/SonoBarKit/Services/DeviceManager.swift
import Foundation
import Observation

/// Manages discovered Sonos devices and group topology.
@Observable
public final class DeviceManager: @unchecked Sendable {
    public private(set) var devices: [SonosDevice] = []
    public private(set) var groups: [ZoneGroup] = []
    public private(set) var activeDevice: SonosDevice?

    private var activeDeviceUUID: String?

    public init() {}

    /// Updates devices and groups from a ZoneGroupState XML string.
    public func updateFromZoneGroupState(_ xml: String) throws {
        let parsedGroups = try ZoneGroupParser.parse(xml)
        self.groups = parsedGroups

        var newDevices: [SonosDevice] = []
        for group in parsedGroups {
            for member in group.members {
                var device = SonosDevice(
                    uuid: member.uuid,
                    ip: member.ip,
                    roomName: member.zoneName
                )
                // Preserve reachability from previous state
                if let existing = devices.first(where: { $0.uuid == member.uuid }) {
                    device.modelName = existing.modelName
                    device.isReachable = existing.isReachable
                }
                newDevices.append(device)
            }
        }
        self.devices = newDevices

        // Restore active device selection
        if let uuid = activeDeviceUUID {
            activeDevice = devices.first(where: { $0.uuid == uuid })
        }
        // Auto-select first device if none selected
        if activeDevice == nil, let first = devices.first {
            setActiveDevice(uuid: first.uuid)
        }
    }

    /// Sets the active device by UUID.
    public func setActiveDevice(uuid: String) {
        activeDeviceUUID = uuid
        activeDevice = devices.first(where: { $0.uuid == uuid })
    }

    /// Returns the coordinator IP for a given device UUID.
    /// All transport commands must be sent to the coordinator.
    public func coordinatorIP(for uuid: String) -> String? {
        for group in groups {
            if group.members.contains(where: { $0.uuid == uuid }) {
                return group.members.first(where: { $0.uuid == group.coordinatorUUID })?.ip
            }
        }
        return nil
    }

    /// Returns the group containing a device, if any.
    public func group(for uuid: String) -> ZoneGroup? {
        groups.first { $0.members.contains(where: { $0.uuid == uuid }) }
    }

    /// Returns whether a device is a group coordinator.
    public func isCoordinator(_ uuid: String) -> Bool {
        groups.contains { $0.coordinatorUUID == uuid }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter DeviceManagerTests
```

Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/ SonoBarKit/Tests/
git commit -m "feat: add DeviceManager for speaker discovery and group tracking"
```

---

### Task 9: PlaybackController

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/PlaybackController.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Services/PlaybackControllerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/SonoBarKitTests/Services/PlaybackControllerTests.swift
import XCTest
@testable import SonoBarKit

final class PlaybackControllerTests: XCTestCase {
    private func makeMockClient() -> (SOAPClient, MockHTTPClient) {
        let mock = MockHTTPClient()
        mock.responseBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body><u:PlayResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"/></s:Body>
        </s:Envelope>
        """
        let client = SOAPClient(host: "192.168.1.50", httpClient: mock)
        return (client, mock)
    }

    func testPlaySendsCorrectAction() async throws {
        let (client, mock) = makeMockClient()
        let controller = PlaybackController(soapClient: client)
        try await controller.play()
        let req = try XCTUnwrap(mock.lastRequest)
        XCTAssertTrue(req.value(forHTTPHeaderField: "SOAPACTION")?.contains("Play") ?? false)
        XCTAssertEqual(req.url?.path, "/MediaRenderer/AVTransport/Control")
    }

    func testPauseSendsCorrectAction() async throws {
        let (client, mock) = makeMockClient()
        let controller = PlaybackController(soapClient: client)
        try await controller.pause()
        let req = try XCTUnwrap(mock.lastRequest)
        XCTAssertTrue(req.value(forHTTPHeaderField: "SOAPACTION")?.contains("Pause") ?? false)
    }

    func testSetVolumeSendsCorrectValue() async throws {
        let (client, mock) = makeMockClient()
        let controller = PlaybackController(soapClient: client)
        try await controller.setVolume(42)
        let body = String(data: mock.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("<DesiredVolume>42</DesiredVolume>"))
        XCTAssertTrue(body.contains("RenderingControl"))
    }

    func testSetVolumeClamps() async throws {
        let (client, mock) = makeMockClient()
        let controller = PlaybackController(soapClient: client)
        try await controller.setVolume(150)
        let body = String(data: mock.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("<DesiredVolume>100</DesiredVolume>"))
    }

    func testGetTransportStateParsesResponse() async throws {
        let mock = MockHTTPClient()
        let transportResponse = """
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
        mock.responseBody = transportResponse
        let client = SOAPClient(host: "192.168.1.50", httpClient: mock)
        let controller = PlaybackController(soapClient: client)
        let state = try await controller.getTransportState()
        XCTAssertEqual(state, .playing)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter PlaybackControllerTests 2>&1 | tail -5
```

- [ ] **Step 3: Implement PlaybackController**

```swift
// Sources/SonoBarKit/Services/PlaybackController.swift
import Foundation

/// Controls playback and volume on a Sonos speaker via SOAP.
public final class PlaybackController: Sendable {
    private let soapClient: SOAPClient

    public init(soapClient: SOAPClient) {
        self.soapClient = soapClient
    }

    // MARK: - Transport Controls

    public func play() async throws {
        _ = try await soapClient.callAction(
            service: .avTransport, action: "Play",
            params: ["InstanceID": "0", "Speed": "1"]
        )
    }

    public func pause() async throws {
        _ = try await soapClient.callAction(
            service: .avTransport, action: "Pause",
            params: ["InstanceID": "0"]
        )
    }

    public func stop() async throws {
        _ = try await soapClient.callAction(
            service: .avTransport, action: "Stop",
            params: ["InstanceID": "0"]
        )
    }

    public func next() async throws {
        _ = try await soapClient.callAction(
            service: .avTransport, action: "Next",
            params: ["InstanceID": "0"]
        )
    }

    public func previous() async throws {
        _ = try await soapClient.callAction(
            service: .avTransport, action: "Previous",
            params: ["InstanceID": "0"]
        )
    }

    public func seek(to time: String) async throws {
        _ = try await soapClient.callAction(
            service: .avTransport, action: "Seek",
            params: ["InstanceID": "0", "Unit": "REL_TIME", "Target": time]
        )
    }

    // MARK: - State Queries

    public func getTransportState() async throws -> TransportState {
        let result = try await soapClient.callAction(
            service: .avTransport, action: "GetTransportInfo",
            params: ["InstanceID": "0"]
        )
        let stateStr = result["CurrentTransportState"] ?? "STOPPED"
        return TransportState(rawValue: stateStr) ?? .stopped
    }

    public func getPositionInfo() async throws -> TrackInfo? {
        let result = try await soapClient.callAction(
            service: .avTransport, action: "GetPositionInfo",
            params: ["InstanceID": "0"]
        )
        return TrackInfo(fromPositionInfo: result)
    }

    // MARK: - Volume

    public func setVolume(_ level: Int) async throws {
        let clamped = max(0, min(100, level))
        _ = try await soapClient.callAction(
            service: .renderingControl, action: "SetVolume",
            params: ["InstanceID": "0", "Channel": "Master", "DesiredVolume": "\(clamped)"]
        )
    }

    public func getVolume() async throws -> Int {
        let result = try await soapClient.callAction(
            service: .renderingControl, action: "GetVolume",
            params: ["InstanceID": "0", "Channel": "Master"]
        )
        return Int(result["CurrentVolume"] ?? "0") ?? 0
    }

    public func setMute(_ muted: Bool) async throws {
        _ = try await soapClient.callAction(
            service: .renderingControl, action: "SetMute",
            params: ["InstanceID": "0", "Channel": "Master", "DesiredMute": muted ? "1" : "0"]
        )
    }

    public func getMute() async throws -> Bool {
        let result = try await soapClient.callAction(
            service: .renderingControl, action: "GetMute",
            params: ["InstanceID": "0", "Channel": "Master"]
        )
        return result["CurrentMute"] == "1"
    }

    // MARK: - Group Volume

    public func setGroupVolume(_ level: Int) async throws {
        let clamped = max(0, min(100, level))
        _ = try await soapClient.callAction(
            service: .groupRenderingControl, action: "SetGroupVolume",
            params: ["InstanceID": "0", "DesiredVolume": "\(clamped)"]
        )
    }

    public func getGroupVolume() async throws -> Int {
        let result = try await soapClient.callAction(
            service: .groupRenderingControl, action: "GetGroupVolume",
            params: ["InstanceID": "0"]
        )
        return Int(result["CurrentVolume"] ?? "0") ?? 0
    }

    // MARK: - Play URI

    public func playURI(_ uri: String, metadata: String = "") async throws {
        _ = try await soapClient.callAction(
            service: .avTransport, action: "SetAVTransportURI",
            params: ["InstanceID": "0", "CurrentURI": uri, "CurrentURIMetaData": metadata]
        )
        try await play()
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter PlaybackControllerTests
```

Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/ SonoBarKit/Tests/
git commit -m "feat: add PlaybackController for transport and volume control"
```

---

### Task 10: GroupManager

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/GroupManager.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Services/GroupManagerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/SonoBarKitTests/Services/GroupManagerTests.swift
import XCTest
@testable import SonoBarKit

final class GroupManagerTests: XCTestCase {
    func testGroupSendsCorrectURI() async throws {
        let mock = MockHTTPClient()
        mock.responseBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body><u:SetAVTransportURIResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"/></s:Body>
        </s:Envelope>
        """
        let memberClient = SOAPClient(host: "192.168.1.51", httpClient: mock)
        let manager = GroupManager()
        try await manager.joinToCoordinator(
            memberClient: memberClient,
            coordinatorUUID: "RINCON_AAA"
        )
        let body = String(data: mock.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("x-rincon:RINCON_AAA"))
    }

    func testUngroupSendsCorrectAction() async throws {
        let mock = MockHTTPClient()
        mock.responseBody = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body><u:BecomeCoordinatorOfStandaloneGroupResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"/></s:Body>
        </s:Envelope>
        """
        let client = SOAPClient(host: "192.168.1.51", httpClient: mock)
        let manager = GroupManager()
        try await manager.ungroup(client: client)
        let body = String(data: mock.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("BecomeCoordinatorOfStandaloneGroup"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter GroupManagerTests 2>&1 | tail -5
```

- [ ] **Step 3: Implement GroupManager**

```swift
// Sources/SonoBarKit/Services/GroupManager.swift
import Foundation

/// Manages grouping and ungrouping of Sonos speakers.
public final class GroupManager: Sendable {
    public init() {}

    /// Joins a speaker to a group by setting its transport URI to the coordinator.
    public func joinToCoordinator(memberClient: SOAPClient, coordinatorUUID: String) async throws {
        _ = try await memberClient.callAction(
            service: .avTransport,
            action: "SetAVTransportURI",
            params: [
                "InstanceID": "0",
                "CurrentURI": "x-rincon:\(coordinatorUUID)",
                "CurrentURIMetaData": ""
            ]
        )
    }

    /// Groups multiple speakers under a coordinator.
    /// Joins each member by setting its transport URI to x-rincon:<coordinatorUUID>.
    public func group(memberIPs: [String], coordinatorUUID: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for ip in memberIPs {
                group.addTask {
                    let client = SOAPClient(host: ip)
                    try await self.joinToCoordinator(memberClient: client, coordinatorUUID: coordinatorUUID)
                }
            }
            try await group.waitForAll()
        }
    }

    /// Removes a speaker from its group, making it standalone.
    public func ungroup(client: SOAPClient) async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "BecomeCoordinatorOfStandaloneGroup",
            params: ["InstanceID": "0"]
        )
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter GroupManagerTests
```

Expected: All 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/ SonoBarKit/Tests/
git commit -m "feat: add GroupManager for speaker grouping/ungrouping"
```

---

## Chunk 3: App Shell + UI

### Task 11: Xcode App Project Setup

**Files:**
- Create: `SonoBar/SonoBarApp.swift`
- Create: `SonoBar/AppDelegate.swift`
- Create: `SonoBar/Info.plist`
- Create: `SonoBar/SonoBar.entitlements`

- [ ] **Step 1: Create the Xcode project using xcodegen or manually**

Create a project config:

```bash
mkdir -p /Users/denver/src/sonos/SonoBar
```

```swift
// SonoBar/SonoBarApp.swift
import SwiftUI

@main
struct SonoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No window — menu bar only
        Settings {
            EmptyView()
        }
    }
}
```

```swift
// SonoBar/AppDelegate.swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hifispeaker.fill", accessibilityDescription: "SonoBar")
            button.action = #selector(togglePopover)
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 450)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView()
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

- [ ] **Step 2: Create Info.plist with LSUIElement**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>SonoBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.sonobar.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
</dict>
</plist>
```

- [ ] **Step 3: Create entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Non-sandboxed: UDP multicast and local HTTP listener require unrestricted network access -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 4: Create stub PopoverContentView**

```swift
// SonoBar/Views/PopoverContentView.swift
import SwiftUI
import SonoBarKit

enum Tab {
    case nowPlaying, rooms, browse, alarms
}

struct PopoverContentView: View {
    @State private var selectedTab: Tab = .nowPlaying

    var body: some View {
        VStack(spacing: 0) {
            // Tab content
            Group {
                switch selectedTab {
                case .nowPlaying:
                    NowPlayingView(navigateToRooms: { selectedTab = .rooms })
                case .rooms:
                    RoomSwitcherView()
                case .browse:
                    Text("Browse").frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundColor(.secondary)
                case .alarms:
                    Text("Alarms").frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Tab bar
            HStack(spacing: 0) {
                tabButton(tab: .nowPlaying, icon: "play.fill", label: "Now")
                tabButton(tab: .rooms, icon: "house.fill", label: "Rooms")
                tabButton(tab: .browse, icon: "books.vertical.fill", label: "Browse")
                tabButton(tab: .alarms, icon: "alarm.fill", label: "Alarms")
            }
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 320, height: 450)
    }

    private func tabButton(tab: Tab, icon: String, label: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.system(size: 10))
            }
            .foregroundColor(selectedTab == tab ? .primary : .secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
```

Note: Browse and Alarms tabs are intentional placeholders — they will be implemented in Phase 2.

- [ ] **Step 5: Commit**

```bash
git add SonoBar/
git commit -m "feat: add macOS menu bar app shell with popover and tab navigation"
```

---

### Task 12: Now Playing View

**Files:**
- Create: `SonoBar/Views/NowPlayingView.swift`
- Create: `SonoBar/Views/VolumeSliderView.swift`
- Modify: `SonoBar/Views/PopoverContentView.swift`

- [ ] **Step 1: Create VolumeSliderView with numeric 0-100 display**

```swift
// SonoBar/Views/VolumeSliderView.swift
import SwiftUI

struct VolumeSliderView: View {
    @Binding var volume: Double
    @Binding var isMuted: Bool
    var onVolumeChange: (Int) -> Void
    var onMuteToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onMuteToggle) {
                Image(systemName: isMuted ? "speaker.slash.fill" : volumeIcon)
                    .font(.system(size: 12))
                    .foregroundColor(isMuted ? .red : .secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)

            Slider(value: $volume, in: 0...100, step: 1) { editing in
                if !editing {
                    onVolumeChange(Int(volume))
                }
            }

            Text("\(Int(volume))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var volumeIcon: String {
        switch Int(volume) {
        case 0: return "speaker.fill"
        case 1...33: return "speaker.wave.1.fill"
        case 34...66: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
```

- [ ] **Step 2: Create NowPlayingView**

```swift
// SonoBar/Views/NowPlayingView.swift
import SwiftUI

struct NowPlayingView: View {
    var navigateToRooms: () -> Void = {}
    var onSeek: ((Double) -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    @State private var roomName = "No Speaker"
    @State private var groupInfo: String? = nil
    @State private var trackTitle = "Not Playing"
    @State private var trackArtist = ""
    @State private var trackAlbum = ""
    @State private var sourceBadge = ""
    @State private var elapsed = "0:00"
    @State private var duration = "0:00"
    @State private var progress: Double = 0
    @State private var isPlaying = false
    @State private var volume: Double = 50
    @State private var isMuted = false

    var body: some View {
        VStack(spacing: 0) {
            // Room selector
            Button(action: navigateToRooms) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(roomName)
                            .font(.system(size: 13, weight: .semibold))
                        if let groupInfo {
                            Text(groupInfo)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            .buttonStyle(.plain)

            // Album art placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 200, height: 200)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                )
                .padding(.bottom, 8)

            // Track info
            VStack(spacing: 2) {
                Text(trackTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(trackArtist.isEmpty ? "" : "\(trackArtist) \u{2014} \(trackAlbum)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !sourceBadge.isEmpty {
                    Text(sourceBadge)
                        .font(.system(size: 10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(10)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)

            // Progress (scrubbable)
            VStack(spacing: 4) {
                Slider(value: $progress, in: 0...1) { editing in
                    if !editing { onSeek?(progress) }
                }
                    .controlSize(.mini)
                HStack {
                    Text(elapsed).font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    Text(duration).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Transport controls
            HStack(spacing: 28) {
                Button(action: { onPrevious?() }) {
                    Image(systemName: "backward.fill").font(.system(size: 16))
                }
                Button(action: { onPlayPause?() }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                }
                Button(action: { onNext?() }) {
                    Image(systemName: "forward.fill").font(.system(size: 16))
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            // Volume
            VolumeSliderView(
                volume: $volume,
                isMuted: $isMuted,
                onVolumeChange: { _ in /* set volume */ },
                onMuteToggle: { isMuted.toggle() }
            )
            .padding(.bottom, 8)
        }
    }
}
```

- [ ] **Step 3: Wire NowPlayingView into PopoverContentView**

Replace the `.nowPlaying` case in PopoverContentView:

```swift
case .nowPlaying:
    NowPlayingView()
```

- [ ] **Step 4: Commit**

```bash
git add SonoBar/Views/
git commit -m "feat: add Now Playing view with transport controls and volume slider"
```

---

### Task 13: Room Switcher View

**Files:**
- Create: `SonoBar/Views/RoomSwitcherView.swift`
- Modify: `SonoBar/Views/PopoverContentView.swift`

- [ ] **Step 1: Create RoomSwitcherView**

```swift
// SonoBar/Views/RoomSwitcherView.swift
import SwiftUI

struct RoomSwitcherView: View {
    // Placeholder data until wired to DeviceManager
    struct RoomItem: Identifiable {
        let id: String
        let name: String
        let status: String
        let isPlaying: Bool
        let isActive: Bool
        let groupBadge: String?
        let icon: String
    }

    @State private var rooms: [RoomItem] = []
    var onSelectRoom: ((String) -> Void)?
    var onUngroup: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Rooms")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if rooms.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hifispeaker.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No Sonos speakers found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Button("Refresh") { /* trigger SSDP scan */ }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rooms) { room in
                            roomRow(room)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private func roomRow(_ room: RoomItem) -> some View {
        Button {
            onSelectRoom?(room.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: room.icon)
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(room.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(room.status)
                        .font(.system(size: 11))
                        .foregroundColor(room.isPlaying ? .accentColor : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let badge = room.groupBadge {
                    Text(badge)
                        .font(.system(size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(room.isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cornerRadius(8)
        .contextMenu {
            if room.groupBadge != nil {
                Button("Ungroup") { onUngroup?(room.id) }
            }
        }
    }
}
```

- [ ] **Step 2: Wire into PopoverContentView**

Replace the `.rooms` case:

```swift
case .rooms:
    RoomSwitcherView()
```

- [ ] **Step 3: Commit**

```bash
git add SonoBar/Views/
git commit -m "feat: add Room Switcher view with empty state"
```

---

### Task 14: Persistence Layer

**Files:**
- Create: `SonoBar/Persistence/SettingsStore.swift`
- Create: `SonoBar/Persistence/ArtworkCache.swift`

- [ ] **Step 1: Create SettingsStore**

```swift
// SonoBar/Persistence/SettingsStore.swift
import Foundation

/// Persists user settings and cached state in UserDefaults.
final class SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Active Room

    var activeDeviceUUID: String? {
        get { defaults.string(forKey: "activeDeviceUUID") }
        set { defaults.set(newValue, forKey: "activeDeviceUUID") }
    }

    // MARK: - Cached Speaker List

    var cachedSpeakers: [[String: String]] {
        get { defaults.array(forKey: "cachedSpeakers") as? [[String: String]] ?? [] }
        set { defaults.set(newValue, forKey: "cachedSpeakers") }
    }

    func saveSpeakers(_ devices: [(uuid: String, ip: String, roomName: String)]) {
        cachedSpeakers = devices.map {
            ["uuid": $0.uuid, "ip": $0.ip, "roomName": $0.roomName]
        }
    }

    func loadCachedSpeakers() -> [(uuid: String, ip: String, roomName: String)] {
        cachedSpeakers.compactMap { dict in
            guard let uuid = dict["uuid"], let ip = dict["ip"], let room = dict["roomName"] else { return nil }
            return (uuid: uuid, ip: ip, roomName: room)
        }
    }

    // MARK: - Launch at Login

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }
}
```

- [ ] **Step 2: Create ArtworkCache**

```swift
// SonoBar/Persistence/ArtworkCache.swift
import Foundation
import AppKit

/// Disk-based LRU cache for album artwork.
final class ArtworkCache {
    private let cacheDir: URL
    private let maxSizeBytes: Int

    init(maxSizeMB: Int = 50) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDir = caches.appendingPathComponent("SonoBar/artwork", isDirectory: true)
        self.maxSizeBytes = maxSizeMB * 1024 * 1024
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Returns cached image for a URL, or nil if not cached.
    func get(for urlString: String) -> NSImage? {
        let file = cacheDir.appendingPathComponent(cacheKey(urlString))
        guard let data = try? Data(contentsOf: file) else { return nil }
        // Touch for LRU
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: file.path
        )
        return NSImage(data: data)
    }

    /// Stores image data for a URL.
    func set(_ data: Data, for urlString: String) {
        let file = cacheDir.appendingPathComponent(cacheKey(urlString))
        try? data.write(to: file)
        evictIfNeeded()
    }

    private func cacheKey(_ urlString: String) -> String {
        let hash = urlString.utf8.reduce(into: UInt64(5381)) { $0 = $0 &* 33 &+ UInt64($1) }
        return String(hash, radix: 16)
    }

    private func evictIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        let totalSize = files.compactMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }.reduce(0, +)

        guard totalSize > maxSizeBytes else { return }

        // Sort by modification date, oldest first
        let sorted = files.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 < d2
        }

        var remaining = totalSize
        for file in sorted {
            guard remaining > maxSizeBytes else { break }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at: file)
            remaining -= size
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add SonoBar/Persistence/
git commit -m "feat: add settings persistence and artwork disk cache"
```

---

### Task 15: Run All Tests and Final Verification

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/denver/src/sonos/SonoBarKit
swift test
```

Expected: All tests pass (SOAPEnvelope, XMLResponseParser, SOAPClient, SSDPParser, UPnPEventListener, Models, DeviceManager, PlaybackController, GroupManager).

- [ ] **Step 2: Verify the app project compiles**

This requires an Xcode project file. Create it via Xcode or a generation tool:

```bash
cd /Users/denver/src/sonos
# If xcodegen is available:
# xcodegen generate
# Otherwise, open Xcode: File > New > Project > macOS > App
# Add SonoBarKit as a local package dependency
```

- [ ] **Step 3: Commit any remaining changes**

```bash
git add -A
git commit -m "chore: Phase 1 MVP complete — all tests passing"
```

---

### Task 16: Wire UI to Service Layer

**Files:**
- Create: `SonoBar/Services/AppState.swift`
- Modify: `SonoBar/AppDelegate.swift`
- Modify: `SonoBar/Views/PopoverContentView.swift`
- Modify: `SonoBar/Views/NowPlayingView.swift`
- Modify: `SonoBar/Views/RoomSwitcherView.swift`

This task connects the UI views to DeviceManager, PlaybackController, and GroupManager.

- [ ] **Step 1: Create AppState as the central observable coordinator**

```swift
// SonoBar/Services/AppState.swift
import SwiftUI
import SonoBarKit

@Observable
final class AppState {
    let deviceManager = DeviceManager()
    let groupManager = GroupManager()
    private let ssdp = SSDPDiscovery()
    private let settings = SettingsStore()
    private var eventListener: UPnPEventListener?

    var playbackState = PlaybackState()
    var isLoading = true

    /// The SOAPClient for the active speaker's group coordinator.
    var activeClient: SOAPClient? {
        guard let device = deviceManager.activeDevice,
              let ip = deviceManager.coordinatorIP(for: device.uuid) else { return nil }
        return SOAPClient(host: ip)
    }

    var activeController: PlaybackController? {
        guard let client = activeClient else { return nil }
        return PlaybackController(soapClient: client)
    }

    func startDiscovery() async {
        // Restore cached speakers immediately
        let cached = settings.loadCachedSpeakers()
        for s in cached {
            let device = SonosDevice(uuid: s.uuid, ip: s.ip, roomName: s.roomName, isReachable: false)
            // DeviceManager will merge these when real discovery completes
        }
        if let savedUUID = settings.activeDeviceUUID {
            deviceManager.setActiveDevice(uuid: savedUUID)
        }

        // Run SSDP discovery
        let results = await ssdp.scan()
        isLoading = false

        if !results.isEmpty {
            // Fetch zone group topology from the first discovered speaker
            let client = SOAPClient(host: results[0].ip)
            if let response = try? await client.callAction(
                service: .zoneGroupTopology,
                action: "GetZoneGroupState",
                params: [:]
            ), let xml = response["ZoneGroupState"] {
                try? deviceManager.updateFromZoneGroupState(xml)
            }
            // Cache for next launch
            settings.saveSpeakers(deviceManager.devices.map {
                (uuid: $0.uuid, ip: $0.ip, roomName: $0.roomName)
            })
        }

        // Refresh playback state
        await refreshPlayback()
    }

    func refreshPlayback() async {
        guard let controller = activeController else { return }
        playbackState.transportState = (try? await controller.getTransportState()) ?? .stopped
        playbackState.currentTrack = try? await controller.getPositionInfo()
        playbackState.volume = (try? await controller.getVolume()) ?? 0
        playbackState.isMuted = (try? await controller.getMute()) ?? false
    }

    func selectRoom(uuid: String) {
        deviceManager.setActiveDevice(uuid: uuid)
        settings.activeDeviceUUID = uuid
        Task { await refreshPlayback() }
    }
}
```

- [ ] **Step 2: Inject AppState into the view hierarchy via AppDelegate**

Update `AppDelegate.swift`:

```swift
// In applicationDidFinishLaunching, replace the popover content:
let appState = AppState()
popover.contentViewController = NSHostingController(
    rootView: PopoverContentView()
        .environment(appState)
)
Task { await appState.startDiscovery() }
```

- [ ] **Step 3: Update views to read from AppState**

In `PopoverContentView`, add `@Environment(AppState.self) private var appState`.
Wire `NowPlayingView` callbacks to `appState.activeController` methods.
Wire `RoomSwitcherView` rooms from `appState.deviceManager.devices`.

This wiring is view-specific and follows standard SwiftUI `@Environment` patterns.

- [ ] **Step 4: Commit**

```bash
git add SonoBar/
git commit -m "feat: wire UI views to SonoBarKit service layer via AppState"
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | Project scaffolding | — |
| 2 | SOAP envelope builder + service definitions | 4 tests |
| 3 | XML response parser | 5 tests |
| 4 | SOAP client (HTTP layer) | 2 tests |
| 5 | SSDP discovery | 3 tests |
| 6 | UPnP event listener | 3 tests |
| 7 | Data models (device, playback, groups) | 5 tests |
| 8 | DeviceManager | 3 tests |
| 9 | PlaybackController | 5 tests |
| 10 | GroupManager | 2 tests |
| 11 | Xcode app shell (menu bar + popover) | — |
| 12 | Now Playing view | — |
| 13 | Room Switcher view | — |
| 14 | Persistence (settings + art cache) | — |
| 15 | Final verification | — |
| 16 | Wire UI to service layer | — |

**Total: 32 unit tests across 16 tasks.**

**Note on Xcode project:** Tasks 11-16 produce Swift source files in `SonoBar/`. To build the app, create an Xcode project (File > New > Project > macOS > App) and add SonoBarKit as a local package dependency (File > Add Package Dependencies > Add Local). The project should be non-sandboxed (see entitlements in Task 11). Set `LSUIElement = YES` in the target's Info tab.

Phase 2 (Content & Scheduling) and Phase 3 (SMAPI) will be planned separately after Phase 1 is stable.
