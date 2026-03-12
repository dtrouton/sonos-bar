# SonoBar Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Browse (Favorites/Playlists/Queue), Alarms & Sleep Timer, and media key support to SonoBar.

**Architecture:** Three independent feature slices built bottom-up: SonoBarKit service layer (TDD), then app-layer wiring and views. Each feature is testable independently. Browse and Alarms each need a DIDL-Lite/XML parser, a service wrapper, AppState methods, and a SwiftUI view. Media Keys is app-layer only.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, macOS 14+, Swift Testing framework, UPnP/SOAP, MediaPlayer framework

**Testing:** Use `bash test.sh` in the `SonoBarKit/` directory (NOT `swift test` directly — the test.sh script passes required framework flags for CommandLineTools environments). After app-layer changes, verify with `xcodebuild -project SonoBar.xcodeproj -scheme SonoBar -configuration Debug build`.

**Key patterns from Phase 1:**
- Service wrappers are `public enum` with `static` methods taking a `SOAPClient` parameter (see `GroupManager`)
- Tests use `CapturingHTTPClient` from `Tests/SonoBarKitTests/TestHelpers.swift` and `makeEmptyResponse(action:service:)`
- Test files use `import Testing` + `@testable import SonoBarKit` (do NOT import Foundation directly — it's re-exported from SonoBarKit)
- SOAP calls use the tuple overload `callAction(service:action:params:[(String,String)])` to preserve parameter order
- XML parsers use `XMLParser` delegate pattern (see `ZoneGroupParser` in `GroupTopology.swift`)

---

## Chunk 1: Content Browsing (SonoBarKit)

### Task 1: ContentItem Model

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Models/ContentItem.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Models/ContentItemTests.swift`

- [ ] **Step 1: Create ContentItem model**

```swift
// SonoBarKit/Sources/SonoBarKit/Models/ContentItem.swift

/// A content item from the Sonos ContentDirectory (favorite, playlist, or queue track).
public struct ContentItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let albumArtURI: String?
    public let resourceURI: String
    public let rawDIDL: String
    public let itemClass: String
    public let description: String?

    public init(
        id: String,
        title: String,
        albumArtURI: String? = nil,
        resourceURI: String,
        rawDIDL: String,
        itemClass: String,
        description: String? = nil
    ) {
        self.id = id
        self.title = title
        self.albumArtURI = albumArtURI
        self.resourceURI = resourceURI
        self.rawDIDL = rawDIDL
        self.itemClass = itemClass
        self.description = description
    }

    /// Whether this item is a container (playlist, album) vs a single track.
    public var isContainer: Bool {
        itemClass.hasPrefix("object.container")
    }
}
```

- [ ] **Step 2: Write test for ContentItem**

```swift
// SonoBarKit/Tests/SonoBarKitTests/Models/ContentItemTests.swift
import Testing
@testable import SonoBarKit

@Suite("ContentItem Tests")
struct ContentItemTests {

    @Test func testContentItemCreation() {
        let item = ContentItem(
            id: "FV:2/3",
            title: "My Playlist",
            albumArtURI: "/getaa?uri=x-sonosapi-hls-static",
            resourceURI: "x-rincon-cpcontainer:FV:2/3",
            rawDIDL: "<DIDL-Lite/>",
            itemClass: "object.container.playlistContainer",
            description: "12 tracks"
        )
        #expect(item.id == "FV:2/3")
        #expect(item.title == "My Playlist")
        #expect(item.isContainer == true)
    }

    @Test func testAudioItemIsNotContainer() {
        let item = ContentItem(
            id: "Q:0/1",
            title: "Song",
            resourceURI: "x-file-cifs://server/song.mp3",
            rawDIDL: "<DIDL-Lite/>",
            itemClass: "object.item.audioItem.musicTrack",
            description: "Artist"
        )
        #expect(item.isContainer == false)
    }
}
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/denver/src/sonos/SonoBarKit && bash test.sh
```

Expected: All tests pass including new ContentItem tests.

- [ ] **Step 4: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Models/ContentItem.swift SonoBarKit/Tests/SonoBarKitTests/Models/ContentItemTests.swift
git commit -m "feat: add ContentItem model for browse content"
```

---

### Task 2: DIDL-Lite Parser

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Models/DIDLParser.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Models/DIDLParserTests.swift`

The DIDL-Lite format is the XML schema Sonos uses for content directory responses. Each `<item>` or `<container>` element represents a content item with metadata. The parser must also capture the raw XML of each element for round-tripping as `CurrentURIMetaData`.

- [ ] **Step 1: Write failing tests**

```swift
// SonoBarKit/Tests/SonoBarKitTests/Models/DIDLParserTests.swift
import Testing
@testable import SonoBarKit

@Suite("DIDLParser Tests")
struct DIDLParserTests {

    @Test func testParseItemsFromDIDL() throws {
        let xml = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
        <item id="FV:2/3" parentID="FV:2" restricted="true">
        <dc:title>BBC Radio 4</dc:title>
        <upnp:class>object.item.audioItem.audioBroadcast</upnp:class>
        <upnp:albumArtURI>/getaa?uri=x-sonosapi-stream</upnp:albumArtURI>
        <dc:creator>BBC</dc:creator>
        <res>x-sonosapi-stream:s24940</res>
        </item>
        </DIDL-Lite>
        """
        let items = try DIDLParser.parse(xml)
        #expect(items.count == 1)
        let item = items[0]
        #expect(item.id == "FV:2/3")
        #expect(item.title == "BBC Radio 4")
        #expect(item.resourceURI == "x-sonosapi-stream:s24940")
        #expect(item.albumArtURI == "/getaa?uri=x-sonosapi-stream")
        #expect(item.description == "BBC")
        #expect(item.itemClass == "object.item.audioItem.audioBroadcast")
        #expect(item.rawDIDL.contains("<dc:title>BBC Radio 4</dc:title>"))
    }

    @Test func testParseContainerFromDIDL() throws {
        let xml = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
        <container id="SQ:3" parentID="SQ:" restricted="true">
        <dc:title>Chill Playlist</dc:title>
        <upnp:class>object.container.playlistContainer</upnp:class>
        <res>x-rincon-cpcontainer:SQ:3</res>
        </container>
        </DIDL-Lite>
        """
        let items = try DIDLParser.parse(xml)
        #expect(items.count == 1)
        #expect(items[0].isContainer == true)
        #expect(items[0].title == "Chill Playlist")
    }

    @Test func testParseEmptyDIDL() throws {
        let xml = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
        </DIDL-Lite>
        """
        let items = try DIDLParser.parse(xml)
        #expect(items.isEmpty)
    }

    @Test func testParseMultipleItems() throws {
        let xml = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
        <item id="Q:0/1" parentID="Q:0" restricted="true">
        <dc:title>Track One</dc:title>
        <upnp:class>object.item.audioItem.musicTrack</upnp:class>
        <dc:creator>Artist A</dc:creator>
        <res>x-file-cifs://server/track1.mp3</res>
        </item>
        <item id="Q:0/2" parentID="Q:0" restricted="true">
        <dc:title>Track Two</dc:title>
        <upnp:class>object.item.audioItem.musicTrack</upnp:class>
        <dc:creator>Artist B</dc:creator>
        <res>x-file-cifs://server/track2.mp3</res>
        </item>
        </DIDL-Lite>
        """
        let items = try DIDLParser.parse(xml)
        #expect(items.count == 2)
        #expect(items[0].title == "Track One")
        #expect(items[1].title == "Track Two")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/denver/src/sonos/SonoBarKit && bash test.sh
```

Expected: FAIL — `DIDLParser` not found.

- [ ] **Step 3: Implement DIDLParser**

```swift
// SonoBarKit/Sources/SonoBarKit/Models/DIDLParser.swift

/// Parses DIDL-Lite XML from Sonos ContentDirectory Browse responses into ContentItem arrays.
public enum DIDLParser {

    /// Parses DIDL-Lite XML and returns an array of ContentItems.
    public static func parse(_ xml: String) throws -> [ContentItem] {
        guard let data = xml.data(using: .utf8) else {
            throw SOAPError(code: -1, message: "Failed to encode DIDL XML as UTF-8")
        }
        let delegate = DIDLXMLDelegate(sourceXML: xml)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? SOAPError(code: -1, message: "DIDL XML parse failed")
        }
        return delegate.items
    }
}

// MARK: - DIDLXMLDelegate

private final class DIDLXMLDelegate: NSObject, XMLParserDelegate {
    var items: [ContentItem] = []
    private let sourceXML: String

    // Current element state
    private var inItem = false
    private var currentID = ""
    private var currentTitle = ""
    private var currentClass = ""
    private var currentArtURI: String?
    private var currentCreator: String?
    private var currentRes: String?
    private var currentText = ""

    // Track the raw XML range for rawDIDL capture
    private var elementStartTag = ""
    private var rawXMLParts: [String] = []

    init(sourceXML: String) {
        self.sourceXML = sourceXML
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""

        if elementName == "item" || elementName == "container" {
            inItem = true
            currentID = attributeDict["id"] ?? ""
            currentTitle = ""
            currentClass = ""
            currentArtURI = nil
            currentCreator = nil
            currentRes = nil
            // Reconstruct opening tag for rawDIDL
            let attrs = attributeDict.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
            elementStartTag = elementName
            rawXMLParts = ["<\(elementName) \(attrs)>"]
        } else if inItem {
            // Collect inner tags for rawDIDL
            if attributeDict.isEmpty {
                rawXMLParts.append("<\(elementName)>")
            } else {
                let attrs = attributeDict.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
                rawXMLParts.append("<\(elementName) \(attrs)>")
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if inItem {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

            switch elementName {
            case "dc:title":
                currentTitle = trimmed
                rawXMLParts.append("\(trimmed)</\(elementName)>")
            case "upnp:class":
                currentClass = trimmed
                rawXMLParts.append("\(trimmed)</\(elementName)>")
            case "upnp:albumArtURI":
                currentArtURI = trimmed.isEmpty ? nil : trimmed
                rawXMLParts.append("\(trimmed)</\(elementName)>")
            case "dc:creator":
                currentCreator = trimmed.isEmpty ? nil : trimmed
                rawXMLParts.append("\(trimmed)</\(elementName)>")
            case "res":
                currentRes = trimmed.isEmpty ? nil : trimmed
                rawXMLParts.append("\(trimmed)</\(elementName)>")
            case "item", "container":
                rawXMLParts.append("</\(elementName)>")
                let rawDIDL = rawXMLParts.joined()
                let item = ContentItem(
                    id: currentID,
                    title: currentTitle,
                    albumArtURI: currentArtURI,
                    resourceURI: currentRes ?? "",
                    rawDIDL: rawDIDL,
                    itemClass: currentClass,
                    description: currentCreator
                )
                items.append(item)
                inItem = false
            default:
                rawXMLParts.append("\(trimmed)</\(elementName)>")
            }
        }
        currentText = ""
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/denver/src/sonos/SonoBarKit && bash test.sh
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Models/DIDLParser.swift SonoBarKit/Tests/SonoBarKitTests/Models/DIDLParserTests.swift
git commit -m "feat: add DIDL-Lite parser for ContentDirectory responses"
```

---

### Task 3: ContentBrowser Service

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/ContentBrowser.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Services/ContentBrowserTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// SonoBarKit/Tests/SonoBarKitTests/Services/ContentBrowserTests.swift
import Testing
@testable import SonoBarKit

@Suite("ContentBrowser Tests")
struct ContentBrowserTests {

    // Helper: wraps DIDL-Lite in a Browse response envelope
    private func makeBrowseResponse(didl: String) -> Data {
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
        <Result>\(didl.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</Result>
        <NumberReturned>1</NumberReturned>
        <TotalMatches>1</TotalMatches>
        </u:BrowseResponse>
        </s:Body>
        </s:Envelope>
        """
        return Data(xml.utf8)
    }

    @Test func testBrowseFavoritesSendsCorrectObjectID() async throws {
        let mock = CapturingHTTPClient()
        let didl = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
        <item id="FV:2/1" parentID="FV:2" restricted="true">
        <dc:title>My Fav</dc:title>
        <upnp:class>object.item.audioItem</upnp:class>
        <res>x-sonosapi-stream:s123</res>
        </item>
        </DIDL-Lite>
        """
        mock.responseData = makeBrowseResponse(didl: didl)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let items = try await ContentBrowser.browseFavorites(client: client)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<ObjectID>FV:2</ObjectID>"))
        #expect(body.contains("<BrowseFlag>BrowseDirectChildren</BrowseFlag>"))
        #expect(items.count == 1)
        #expect(items[0].title == "My Fav")
    }

    @Test func testBrowsePlaylistsSendsCorrectObjectID() async throws {
        let mock = CapturingHTTPClient()
        let didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"></DIDL-Lite>
        """
        mock.responseData = makeBrowseResponse(didl: didl)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        _ = try await ContentBrowser.browsePlaylists(client: client)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<ObjectID>SQ:</ObjectID>"))
    }

    @Test func testBrowseQueueSendsCorrectObjectID() async throws {
        let mock = CapturingHTTPClient()
        let didl = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"></DIDL-Lite>
        """
        mock.responseData = makeBrowseResponse(didl: didl)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        _ = try await ContentBrowser.browseQueue(client: client)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<ObjectID>Q:0</ObjectID>"))
    }

    @Test func testPlayItemSendsSetAVTransportURI() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "SetAVTransportURI", service: .avTransport)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let item = ContentItem(
            id: "FV:2/3",
            title: "Test",
            resourceURI: "x-sonosapi-stream:s123",
            rawDIDL: "<item><dc:title>Test</dc:title></item>",
            itemClass: "object.item.audioItem"
        )

        // playItem calls SetAVTransportURI then Play — mock needs to handle both
        // We just verify the first call (SetAVTransportURI)
        try await ContentBrowser.playItem(client: client, item: item)

        let body = try #require(mock.lastBodyString)
        // Last call will be Play, so check it went through
        #expect(body.contains("<u:Play") || body.contains("<u:SetAVTransportURI"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/denver/src/sonos/SonoBarKit && bash test.sh
```

Expected: FAIL — `ContentBrowser` not found.

- [ ] **Step 3: Implement ContentBrowser**

```swift
// SonoBarKit/Sources/SonoBarKit/Services/ContentBrowser.swift

/// Browses Sonos ContentDirectory for favorites, playlists, and queue.
public enum ContentBrowser {

    /// Browses Sonos Favorites (ObjectID: FV:2).
    public static func browseFavorites(client: SOAPClient) async throws -> [ContentItem] {
        try await browse(client: client, objectID: "FV:2")
    }

    /// Browses Sonos Playlists (ObjectID: SQ:).
    public static func browsePlaylists(client: SOAPClient) async throws -> [ContentItem] {
        try await browse(client: client, objectID: "SQ:")
    }

    /// Browses the current queue (ObjectID: Q:0).
    public static func browseQueue(client: SOAPClient) async throws -> [ContentItem] {
        try await browse(client: client, objectID: "Q:0")
    }

    /// Plays a content item by setting its URI and starting playback.
    public static func playItem(client: SOAPClient, item: ContentItem) async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "SetAVTransportURI",
            params: [
                ("InstanceID", "0"),
                ("CurrentURI", item.resourceURI),
                ("CurrentURIMetaData", item.rawDIDL)
            ]
        )
        _ = try await client.callAction(
            service: .avTransport,
            action: "Play",
            params: [("InstanceID", "0"), ("Speed", "1")]
        )
    }

    // MARK: - Private

    private static func browse(client: SOAPClient, objectID: String) async throws -> [ContentItem] {
        let result = try await client.callAction(
            service: .contentDirectory,
            action: "Browse",
            params: [
                ("ObjectID", objectID),
                ("BrowseFlag", "BrowseDirectChildren"),
                ("Filter", "dc:title,res,upnp:albumArtURI,upnp:class,dc:creator"),
                ("StartingIndex", "0"),
                ("RequestedCount", "100"),
                ("SortCriteria", "")
            ]
        )
        guard let didlXML = result["Result"] else { return [] }
        return try DIDLParser.parse(didlXML)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/denver/src/sonos/SonoBarKit && bash test.sh
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/ContentBrowser.swift SonoBarKit/Tests/SonoBarKitTests/Services/ContentBrowserTests.swift
git commit -m "feat: add ContentBrowser service for favorites, playlists, and queue"
```

---

## Chunk 2: Alarms & Sleep Timer (SonoBarKit)

### Task 4: SonosAlarm Model

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Models/SonosAlarm.swift`

- [ ] **Step 1: Create SonosAlarm model**

```swift
// SonoBarKit/Sources/SonoBarKit/Models/SonosAlarm.swift

/// A Sonos alarm definition.
public struct SonosAlarm: Identifiable, Sendable, Equatable {
    public let id: String
    public let startLocalTime: String
    public let recurrence: String
    public let roomUUID: String
    public let programURI: String
    public let programMetaData: String
    public let playMode: String
    public let volume: Int
    public let duration: String
    public let enabled: Bool
    public let includeLinkedZones: Bool

    public init(
        id: String,
        startLocalTime: String,
        recurrence: String,
        roomUUID: String,
        programURI: String,
        programMetaData: String = "",
        playMode: String = "NORMAL",
        volume: Int,
        duration: String = "01:00:00",
        enabled: Bool = true,
        includeLinkedZones: Bool = false
    ) {
        self.id = id
        self.startLocalTime = startLocalTime
        self.recurrence = recurrence
        self.roomUUID = roomUUID
        self.programURI = programURI
        self.programMetaData = programMetaData
        self.playMode = playMode
        self.volume = volume
        self.duration = duration
        self.enabled = enabled
        self.includeLinkedZones = includeLinkedZones
    }

    /// Human-readable recurrence text.
    public var recurrenceText: String {
        switch recurrence {
        case "DAILY": return "Daily"
        case "WEEKDAYS": return "Weekdays"
        case "WEEKENDS": return "Weekends"
        case "ONCE": return "Once"
        default:
            // ON_0123456 format: 0=Sun, 1=Mon, ..., 6=Sat
            if recurrence.hasPrefix("ON_") {
                let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                let digits = recurrence.dropFirst(3)
                let names = digits.compactMap { c -> String? in
                    guard let idx = Int(String(c)), idx >= 0, idx <= 6 else { return nil }
                    return dayNames[idx]
                }
                return names.joined(separator: ", ")
            }
            return recurrence
        }
    }

    /// The start time formatted for display (e.g., "7:00 AM").
    public var displayTime: String {
        let parts = startLocalTime.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return startLocalTime
        }
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h12, minute, ampm)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Models/SonosAlarm.swift
git commit -m "feat: add SonosAlarm model with recurrence and display helpers"
```

---

### Task 5: AlarmScheduler Service

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/AlarmScheduler.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Services/AlarmSchedulerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// SonoBarKit/Tests/SonoBarKitTests/Services/AlarmSchedulerTests.swift
import Testing
@testable import SonoBarKit

@Suite("AlarmScheduler Tests")
struct AlarmSchedulerTests {

    private func makeListAlarmsResponse() -> Data {
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:ListAlarmsResponse xmlns:u="urn:schemas-upnp-org:service:AlarmClock:1">
        <CurrentAlarmList>&lt;Alarms&gt;&lt;Alarm ID="1" StartLocalTime="07:00:00" Duration="01:00:00" Recurrence="WEEKDAYS" Enabled="1" RoomUUID="RINCON_AAA" ProgramURI="x-rincon-buzzer:0" ProgramMetaData="" PlayMode="NORMAL" Volume="20" IncludeLinkedZones="0"/&gt;&lt;/Alarms&gt;</CurrentAlarmList>
        </u:ListAlarmsResponse>
        </s:Body>
        </s:Envelope>
        """
        return Data(xml.utf8)
    }

    @Test func testListAlarmsParsesResponse() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeListAlarmsResponse()
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let alarms = try await AlarmScheduler.listAlarms(client: client)

        #expect(alarms.count == 1)
        let alarm = alarms[0]
        #expect(alarm.id == "1")
        #expect(alarm.startLocalTime == "07:00:00")
        #expect(alarm.recurrence == "WEEKDAYS")
        #expect(alarm.enabled == true)
        #expect(alarm.volume == 20)
        #expect(alarm.roomUUID == "RINCON_AAA")
    }

    @Test func testCreateAlarmSendsCorrectParams() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "CreateAlarm", service: .alarmClock)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let alarm = SonosAlarm(
            id: "",
            startLocalTime: "07:00:00",
            recurrence: "WEEKDAYS",
            roomUUID: "RINCON_AAA",
            programURI: "x-rincon-buzzer:0",
            volume: 20
        )

        try await AlarmScheduler.createAlarm(client: client, alarm: alarm)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:CreateAlarm"))
        #expect(body.contains("<StartLocalTime>07:00:00</StartLocalTime>"))
        #expect(body.contains("<Recurrence>WEEKDAYS</Recurrence>"))
        #expect(body.contains("<RoomUUID>RINCON_AAA</RoomUUID>"))
        #expect(body.contains("<PlayMode>NORMAL</PlayMode>"))
        #expect(body.contains("<Volume>20</Volume>"))
        #expect(body.contains("<Enabled>1</Enabled>"))
    }

    @Test func testDeleteAlarmSendsCorrectID() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "DestroyAlarm", service: .alarmClock)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        try await AlarmScheduler.deleteAlarm(client: client, id: "42")

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:DestroyAlarm"))
        #expect(body.contains("<ID>42</ID>"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/denver/src/sonos/SonoBarKit && bash test.sh
```

Expected: FAIL — `AlarmScheduler` not found.

- [ ] **Step 3: Implement AlarmScheduler**

```swift
// SonoBarKit/Sources/SonoBarKit/Services/AlarmScheduler.swift

/// Manages Sonos alarms via the AlarmClock UPnP service.
public enum AlarmScheduler {

    /// Lists all alarms configured on the Sonos system.
    public static func listAlarms(client: SOAPClient) async throws -> [SonosAlarm] {
        let result = try await client.callAction(
            service: .alarmClock,
            action: "ListAlarms",
            params: [:]
        )
        guard let alarmXML = result["CurrentAlarmList"] else { return [] }
        return try AlarmListParser.parse(alarmXML)
    }

    /// Creates a new alarm.
    public static func createAlarm(client: SOAPClient, alarm: SonosAlarm) async throws {
        _ = try await client.callAction(
            service: .alarmClock,
            action: "CreateAlarm",
            params: alarmParams(alarm)
        )
    }

    /// Updates an existing alarm (must include alarm ID).
    public static func updateAlarm(client: SOAPClient, alarm: SonosAlarm) async throws {
        var params = alarmParams(alarm)
        params.insert(("ID", alarm.id), at: 0)
        _ = try await client.callAction(
            service: .alarmClock,
            action: "UpdateAlarm",
            params: params
        )
    }

    /// Deletes an alarm by ID.
    public static func deleteAlarm(client: SOAPClient, id: String) async throws {
        _ = try await client.callAction(
            service: .alarmClock,
            action: "DestroyAlarm",
            params: [("ID", id)]
        )
    }

    private static func alarmParams(_ alarm: SonosAlarm) -> [(String, String)] {
        [
            ("StartLocalTime", alarm.startLocalTime),
            ("Duration", alarm.duration),
            ("Recurrence", alarm.recurrence),
            ("Enabled", alarm.enabled ? "1" : "0"),
            ("RoomUUID", alarm.roomUUID),
            ("ProgramURI", alarm.programURI),
            ("ProgramMetaData", alarm.programMetaData),
            ("PlayMode", alarm.playMode),
            ("Volume", "\(alarm.volume)"),
            ("IncludeLinkedZones", alarm.includeLinkedZones ? "1" : "0")
        ]
    }
}

// MARK: - AlarmListParser

/// Parses the XML alarm list from ListAlarms response.
enum AlarmListParser {
    static func parse(_ xml: String) throws -> [SonosAlarm] {
        guard let data = xml.data(using: .utf8) else {
            throw SOAPError(code: -1, message: "Failed to encode alarm XML")
        }
        let delegate = AlarmXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? SOAPError(code: -1, message: "Alarm XML parse failed")
        }
        return delegate.alarms
    }
}

private final class AlarmXMLDelegate: NSObject, XMLParserDelegate {
    var alarms: [SonosAlarm] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attr: [String: String] = [:]
    ) {
        guard elementName == "Alarm" else { return }
        let alarm = SonosAlarm(
            id: attr["ID"] ?? "",
            startLocalTime: attr["StartLocalTime"] ?? "",
            recurrence: attr["Recurrence"] ?? "DAILY",
            roomUUID: attr["RoomUUID"] ?? "",
            programURI: attr["ProgramURI"] ?? "",
            programMetaData: attr["ProgramMetaData"] ?? "",
            playMode: attr["PlayMode"] ?? "NORMAL",
            volume: Int(attr["Volume"] ?? "20") ?? 20,
            duration: attr["Duration"] ?? "01:00:00",
            enabled: attr["Enabled"] == "1",
            includeLinkedZones: attr["IncludeLinkedZones"] == "1"
        )
        alarms.append(alarm)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/denver/src/sonos/SonoBarKit && bash test.sh
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/AlarmScheduler.swift SonoBarKit/Tests/SonoBarKitTests/Services/AlarmSchedulerTests.swift
git commit -m "feat: add AlarmScheduler service for alarm CRUD"
```

---

### Task 6: SleepTimerController Service

**Files:**
- Create: `SonoBarKit/Sources/SonoBarKit/Services/SleepTimerController.swift`
- Test: `SonoBarKit/Tests/SonoBarKitTests/Services/SleepTimerControllerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// SonoBarKit/Tests/SonoBarKitTests/Services/SleepTimerControllerTests.swift
import Testing
@testable import SonoBarKit

@Suite("SleepTimerController Tests")
struct SleepTimerControllerTests {

    @Test func testSetSleepTimerConvertsMinutesToHMS() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "ConfigureSleepTimer", service: .avTransport)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        try await SleepTimerController.setSleepTimer(client: client, minutes: 45)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<u:ConfigureSleepTimer"))
        #expect(body.contains("<NewSleepTimerDuration>00:45:00</NewSleepTimerDuration>"))
    }

    @Test func testSetSleepTimerHandlesHours() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "ConfigureSleepTimer", service: .avTransport)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        try await SleepTimerController.setSleepTimer(client: client, minutes: 90)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<NewSleepTimerDuration>01:30:00</NewSleepTimerDuration>"))
    }

    @Test func testGetRemainingTimeReturnsString() async throws {
        let mock = CapturingHTTPClient()
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:GetRemainingSleepTimerDurationResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
        <RemainSleepTimerDuration>00:23:45</RemainSleepTimerDuration>
        </u:GetRemainingSleepTimerDurationResponse>
        </s:Body>
        </s:Envelope>
        """
        mock.responseData = Data(xml.utf8)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let remaining = try await SleepTimerController.getRemainingTime(client: client)
        #expect(remaining == "00:23:45")
    }

    @Test func testGetRemainingTimeReturnsNilWhenEmpty() async throws {
        let mock = CapturingHTTPClient()
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
        <u:GetRemainingSleepTimerDurationResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
        <RemainSleepTimerDuration></RemainSleepTimerDuration>
        </u:GetRemainingSleepTimerDurationResponse>
        </s:Body>
        </s:Envelope>
        """
        mock.responseData = Data(xml.utf8)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        let remaining = try await SleepTimerController.getRemainingTime(client: client)
        #expect(remaining == nil)
    }

    @Test func testCancelSleepTimerSendsEmptyDuration() async throws {
        let mock = CapturingHTTPClient()
        mock.responseData = makeEmptyResponse(action: "ConfigureSleepTimer", service: .avTransport)
        let client = SOAPClient(host: "192.168.1.10", httpClient: mock)

        try await SleepTimerController.cancelSleepTimer(client: client)

        let body = try #require(mock.lastBodyString)
        #expect(body.contains("<NewSleepTimerDuration></NewSleepTimerDuration>"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/denver/src/sonos/SonoBarKit && bash test.sh
```

- [ ] **Step 3: Implement SleepTimerController**

```swift
// SonoBarKit/Sources/SonoBarKit/Services/SleepTimerController.swift

/// Controls the Sonos sleep timer via AVTransport.
public enum SleepTimerController {

    /// Sets a sleep timer for the given number of minutes.
    public static func setSleepTimer(client: SOAPClient, minutes: Int) async throws {
        let hours = minutes / 60
        let mins = minutes % 60
        let duration = String(format: "%02d:%02d:00", hours, mins)
        _ = try await client.callAction(
            service: .avTransport,
            action: "ConfigureSleepTimer",
            params: [("InstanceID", "0"), ("NewSleepTimerDuration", duration)]
        )
    }

    /// Gets the remaining sleep timer duration as "HH:MM:SS", or nil if no timer active.
    public static func getRemainingTime(client: SOAPClient) async throws -> String? {
        let result = try await client.callAction(
            service: .avTransport,
            action: "GetRemainingSleepTimerDuration",
            params: [("InstanceID", "0")]
        )
        guard let remaining = result["RemainSleepTimerDuration"],
              !remaining.isEmpty else { return nil }
        return remaining
    }

    /// Cancels the active sleep timer.
    public static func cancelSleepTimer(client: SOAPClient) async throws {
        _ = try await client.callAction(
            service: .avTransport,
            action: "ConfigureSleepTimer",
            params: [("InstanceID", "0"), ("NewSleepTimerDuration", "")]
        )
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/denver/src/sonos/SonoBarKit && bash test.sh
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add SonoBarKit/Sources/SonoBarKit/Services/SleepTimerController.swift SonoBarKit/Tests/SonoBarKitTests/Services/SleepTimerControllerTests.swift
git commit -m "feat: add SleepTimerController for sleep timer set/get/cancel"
```

---

## Chunk 3: App Layer — Browse & Alarms Views

### Task 7: AppState Additions

**Files:**
- Modify: `SonoBar/Services/AppState.swift`

Add browse, alarm, and sleep timer methods to AppState. These wrap the SonoBarKit services and expose results as observable properties for the views.

- [ ] **Step 1: Add browse properties and methods**

Add to `AppState`:

```swift
var contentItems: [ContentItem] = []
var contentError: String? = nil

func browseFavorites() async {
    contentError = nil
    guard let client = activeClient else { return }
    do {
        contentItems = try await ContentBrowser.browseFavorites(client: client)
    } catch {
        contentError = "Failed to load favorites"
    }
}

func browsePlaylists() async {
    contentError = nil
    guard let client = activeClient else { return }
    do {
        contentItems = try await ContentBrowser.browsePlaylists(client: client)
    } catch {
        contentError = "Failed to load playlists"
    }
}

func browseQueue() async {
    contentError = nil
    guard let client = activeClient else { return }
    do {
        contentItems = try await ContentBrowser.browseQueue(client: client)
    } catch {
        contentError = "Failed to load queue"
    }
}

func playItem(_ item: ContentItem) async {
    guard let client = activeClient else { return }
    do {
        try await ContentBrowser.playItem(client: client, item: item)
        await refreshPlayback()
    } catch {
        contentError = "Failed to play \(item.title)"
    }
}
```

Note: `activeClient` is a private computed property that needs to be re-added (it was removed in the Phase 1 review fix). Add it back as a private helper:

```swift
private var activeClient: SOAPClient? {
    guard let device = deviceManager.activeDevice,
          let ip = deviceManager.coordinatorIP(for: device.uuid) else { return nil }
    return SOAPClient(host: ip)
}
```

- [ ] **Step 2: Add alarm properties and methods**

Add to `AppState`:

```swift
var alarms: [SonosAlarm] = []
var sleepTimerRemaining: String? = nil

func fetchAlarms() async {
    guard let client = activeClient else { return }
    alarms = (try? await AlarmScheduler.listAlarms(client: client)) ?? []
}

func createAlarm(_ alarm: SonosAlarm) async {
    guard let client = activeClient else { return }
    try? await AlarmScheduler.createAlarm(client: client, alarm: alarm)
    await fetchAlarms()
}

func toggleAlarm(_ alarm: SonosAlarm) async {
    guard let client = activeClient else { return }
    let toggled = SonosAlarm(
        id: alarm.id,
        startLocalTime: alarm.startLocalTime,
        recurrence: alarm.recurrence,
        roomUUID: alarm.roomUUID,
        programURI: alarm.programURI,
        programMetaData: alarm.programMetaData,
        playMode: alarm.playMode,
        volume: alarm.volume,
        duration: alarm.duration,
        enabled: !alarm.enabled,
        includeLinkedZones: alarm.includeLinkedZones
    )
    try? await AlarmScheduler.updateAlarm(client: client, alarm: toggled)
    await fetchAlarms()
}

func deleteAlarm(_ alarm: SonosAlarm) async {
    guard let client = activeClient else { return }
    try? await AlarmScheduler.deleteAlarm(client: client, id: alarm.id)
    await fetchAlarms()
}

func setSleepTimer(minutes: Int) async {
    guard let client = activeClient else { return }
    try? await SleepTimerController.setSleepTimer(client: client, minutes: minutes)
    await refreshSleepTimer()
}

func cancelSleepTimer() async {
    guard let client = activeClient else { return }
    try? await SleepTimerController.cancelSleepTimer(client: client)
    sleepTimerRemaining = nil
}

func refreshSleepTimer() async {
    guard let client = activeClient else { return }
    sleepTimerRemaining = try? await SleepTimerController.getRemainingTime(client: client)
}
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project /Users/denver/src/sonos/SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add SonoBar/Services/AppState.swift
git commit -m "feat: add browse, alarm, and sleep timer methods to AppState"
```

---

### Task 8: Browse View

**Files:**
- Create: `SonoBar/Views/BrowseView.swift`
- Create: `SonoBar/Views/ContentGridView.swift`
- Create: `SonoBar/Views/ContentListView.swift`
- Modify: `SonoBar/Views/PopoverContentView.swift`

- [ ] **Step 1: Create ContentGridView (3-column artwork grid for favorites)**

```swift
// SonoBar/Views/ContentGridView.swift
import SwiftUI
import SonoBarKit

struct ContentGridView: View {
    let items: [ContentItem]
    var onTap: (ContentItem) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    Button { onTap(item) } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 20))
                                        .foregroundColor(.secondary)
                                )
                            Text(item.title)
                                .font(.system(size: 10))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}
```

- [ ] **Step 2: Create ContentListView (list for playlists and queue)**

```swift
// SonoBar/Views/ContentListView.swift
import SwiftUI
import SonoBarKit

struct ContentListView: View {
    let items: [ContentItem]
    var currentTrackURI: String?
    var onTap: (ContentItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(items) { item in
                    Button { onTap(item) } label: {
                        HStack(spacing: 10) {
                            if item.resourceURI == currentTrackURI {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 16)
                            } else {
                                Color.clear.frame(width: 16, height: 1)
                            }

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: item.isContainer ? "music.note.list" : "music.note")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                if let desc = item.description {
                                    Text(desc)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Create BrowseView with search and segments**

```swift
// SonoBar/Views/BrowseView.swift
import SwiftUI
import SonoBarKit

enum BrowseSegment: String, CaseIterable {
    case favorites = "Favorites"
    case playlists = "Playlists"
    case queue = "Queue"
}

struct BrowseView: View {
    @Environment(AppState.self) private var appState
    @State private var segment: BrowseSegment = .favorites
    @State private var searchText = ""

    private var filteredItems: [ContentItem] {
        if searchText.isEmpty { return appState.contentItems }
        return appState.contentItems.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Segment picker
            Picker("", selection: $segment) {
                ForEach(BrowseSegment.allCases, id: \.self) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Content
            if let error = appState.contentError {
                VStack(spacing: 8) {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("Retry") { Task { await loadContent() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if segment == .favorites {
                ContentGridView(items: filteredItems) { item in
                    Task { await appState.playItem(item) }
                }
            } else {
                ContentListView(
                    items: filteredItems,
                    currentTrackURI: segment == .queue ? appState.playbackState.currentTrack?.uri : nil
                ) { item in
                    Task {
                        if segment == .queue {
                            // Jump to track in queue
                            guard let idx = appState.contentItems.firstIndex(where: { $0.id == item.id }) else { return }
                            try? await appState.activeController?.seek(to: "\(idx + 1)")
                            await appState.refreshPlayback()
                        } else {
                            await appState.playItem(item)
                        }
                    }
                }
            }
        }
        .onAppear { Task { await loadContent() } }
        .onChange(of: segment) { _, _ in
            searchText = ""
            Task { await loadContent() }
        }
    }

    private var emptyMessage: String {
        switch segment {
        case .favorites: return "No favorites found"
        case .playlists: return "No playlists"
        case .queue: return "Queue is empty"
        }
    }

    private func loadContent() async {
        switch segment {
        case .favorites: await appState.browseFavorites()
        case .playlists: await appState.browsePlaylists()
        case .queue: await appState.browseQueue()
        }
    }
}
```

- [ ] **Step 4: Wire BrowseView into PopoverContentView**

Replace the `.browse` case in `PopoverContentView.swift`:

```swift
case .browse:
    BrowseView()
```

- [ ] **Step 5: Verify build**

```bash
xcodebuild -project /Users/denver/src/sonos/SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 6: Commit**

```bash
git add SonoBar/Views/BrowseView.swift SonoBar/Views/ContentGridView.swift SonoBar/Views/ContentListView.swift SonoBar/Views/PopoverContentView.swift
git commit -m "feat: add Browse tab with favorites grid, playlists list, and queue"
```

---

### Task 9: Alarms & Sleep Timer View

**Files:**
- Create: `SonoBar/Views/AlarmsView.swift`
- Create: `SonoBar/Views/AlarmFormView.swift`
- Modify: `SonoBar/Views/PopoverContentView.swift`

- [ ] **Step 1: Create AlarmsView**

```swift
// SonoBar/Views/AlarmsView.swift
import SwiftUI
import SonoBarKit

struct AlarmsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddForm = false

    var body: some View {
        VStack(spacing: 0) {
            // Sleep Timer section
            VStack(spacing: 8) {
                HStack {
                    Text("Sleep Timer")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }

                if let remaining = appState.sleepTimerRemaining {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.accentColor)
                        Text("\(remaining) remaining")
                            .font(.system(size: 12))
                        Spacer()
                        Button("Cancel") {
                            Task { await appState.cancelSleepTimer() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach([15, 30, 45, 60], id: \.self) { mins in
                            Button("\(mins)m") {
                                Task { await appState.setSleepTimer(minutes: mins) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Alarms section
            HStack {
                Text("Alarms")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { showingAddForm = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if appState.alarms.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "alarm")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No alarms set")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.alarms) { alarm in
                            alarmRow(alarm)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .onAppear {
            Task {
                await appState.fetchAlarms()
                await appState.refreshSleepTimer()
            }
        }
        .sheet(isPresented: $showingAddForm) {
            AlarmFormView()
        }
    }

    private func alarmRow(_ alarm: SonosAlarm) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.displayTime)
                    .font(.system(size: 18, weight: .medium).monospacedDigit())
                Text(alarm.recurrenceText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(roomName(for: alarm.roomUUID))
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { alarm.enabled },
                set: { _ in Task { await appState.toggleAlarm(alarm) } }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contextMenu {
            Button("Delete", role: .destructive) {
                Task { await appState.deleteAlarm(alarm) }
            }
        }
    }

    private func roomName(for uuid: String) -> String {
        appState.deviceManager.devices.first { $0.uuid == uuid }?.roomName ?? "Unknown Room"
    }
}
```

- [ ] **Step 2: Create AlarmFormView**

```swift
// SonoBar/Views/AlarmFormView.swift
import SwiftUI
import SonoBarKit

struct AlarmFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime = Date()
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5] // Weekdays
    @State private var selectedRoomUUID = ""
    @State private var volume: Double = 20
    @State private var programURI = "x-rincon-buzzer:0"

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 12) {
            Text("New Alarm")
                .font(.system(size: 14, weight: .semibold))

            DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)

            // Day selector
            VStack(alignment: .leading, spacing: 6) {
                Text("Days").font(.system(size: 11, weight: .medium))
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { day in
                        Button(dayNames[day]) {
                            if selectedDays.contains(day) {
                                selectedDays.remove(day)
                            } else {
                                selectedDays.insert(day)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(selectedDays.contains(day) ? .accentColor : .secondary)
                    }
                }
                HStack(spacing: 8) {
                    Button("Weekdays") { selectedDays = [1, 2, 3, 4, 5] }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button("Daily") { selectedDays = Set(0...6) }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
            }

            // Room picker
            Picker("Room", selection: $selectedRoomUUID) {
                ForEach(appState.deviceManager.devices) { device in
                    Text(device.roomName).tag(device.uuid)
                }
            }
            .pickerStyle(.menu)

            // Volume
            VolumeSliderView(
                volume: $volume,
                isMuted: .constant(false),
                onVolumeChange: { _ in },
                onMuteToggle: {}
            )

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    Task {
                        await saveAlarm()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            if selectedRoomUUID.isEmpty {
                selectedRoomUUID = appState.deviceManager.activeDevice?.uuid ?? ""
            }
        }
    }

    private func saveAlarm() async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selectedTime)
        let minute = calendar.component(.minute, from: selectedTime)
        let timeStr = String(format: "%02d:%02d:00", hour, minute)

        let recurrence: String
        if selectedDays.count == 7 {
            recurrence = "DAILY"
        } else if selectedDays == [1, 2, 3, 4, 5] {
            recurrence = "WEEKDAYS"
        } else if selectedDays == [0, 6] {
            recurrence = "WEEKENDS"
        } else {
            recurrence = "ON_" + selectedDays.sorted().map(String.init).joined()
        }

        let alarm = SonosAlarm(
            id: "",
            startLocalTime: timeStr,
            recurrence: recurrence,
            roomUUID: selectedRoomUUID,
            programURI: programURI,
            volume: Int(volume)
        )
        await appState.createAlarm(alarm)
    }
}
```

- [ ] **Step 3: Wire AlarmsView into PopoverContentView**

Replace the `.alarms` case in `PopoverContentView.swift`:

```swift
case .alarms:
    AlarmsView()
```

- [ ] **Step 4: Verify build**

```bash
xcodebuild -project /Users/denver/src/sonos/SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 5: Commit**

```bash
git add SonoBar/Views/AlarmsView.swift SonoBar/Views/AlarmFormView.swift SonoBar/Views/PopoverContentView.swift
git commit -m "feat: add Alarms & Sleep Timer tab with alarm CRUD and quick-set timers"
```

---

## Chunk 4: Media Keys & Final Integration

### Task 10: MediaKeyController

**Files:**
- Create: `SonoBar/Controllers/MediaKeyController.swift`
- Modify: `SonoBar/Services/AppState.swift`
- Modify: `SonoBar/AppDelegate.swift`

- [ ] **Step 1: Create MediaKeyController**

```swift
// SonoBar/Controllers/MediaKeyController.swift
import Foundation
import MediaPlayer
import SonoBarKit

/// Manages media key registration and Now Playing info for macOS.
@MainActor
final class MediaKeyController {
    private var isActive = false
    private var commandCenter: MPRemoteCommandCenter { .shared() }
    private var infoCenter: MPNowPlayingInfoCenter { .default() }

    // Callbacks for transport commands
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    func activate(track: TrackInfo?, transportState: TransportState) {
        guard !isActive else {
            updateNowPlaying(track: track, transportState: transportState)
            return
        }
        isActive = true

        // Must set now playing info BEFORE registering handlers
        updateNowPlaying(track: track, transportState: transportState)

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onPlayPause?()
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNext?()
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPrevious?()
            return .success
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)

        infoCenter.nowPlayingInfo = nil
    }

    func updateNowPlaying(track: TrackInfo?, transportState: TransportState) {
        guard isActive else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track?.title ?? "SonoBar"
        info[MPMediaItemPropertyArtist] = track?.artist ?? ""
        info[MPMediaItemPropertyAlbumTitle] = track?.album ?? ""
        info[MPNowPlayingInfoPropertyPlaybackRate] = transportState == .playing ? 1.0 : 0.0
        infoCenter.nowPlayingInfo = info
    }
}
```

- [ ] **Step 2: Wire MediaKeyController into AppState**

Add to `AppState`:

```swift
let mediaKeyController = MediaKeyController()
```

In `refreshPlayback()`, after updating `playbackState`, add:

```swift
mediaKeyController.updateNowPlaying(
    track: currentTrack,
    transportState: transportState
)
```

Set up the callbacks in `startDiscovery()` or an `init` method:

```swift
// In startDiscovery or a setup method:
mediaKeyController.onPlayPause = { [weak self] in
    guard let self else { return }
    Task {
        if self.playbackState.transportState == .playing {
            try? await self.activeController?.pause()
        } else {
            try? await self.activeController?.play()
        }
        await self.refreshPlayback()
    }
}
mediaKeyController.onNext = { [weak self] in
    guard let self else { return }
    Task {
        try? await self.activeController?.next()
        await self.refreshPlayback()
    }
}
mediaKeyController.onPrevious = { [weak self] in
    guard let self else { return }
    Task {
        try? await self.activeController?.previous()
        await self.refreshPlayback()
    }
}
```

- [ ] **Step 3: Wire popover show/close to MediaKeyController in AppDelegate**

Update `togglePopover()` in `AppDelegate`:

```swift
@objc private func togglePopover() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
        popover.performClose(nil)
        appState.mediaKeyController.deactivate()
    } else {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        appState.mediaKeyController.activate(
            track: appState.playbackState.currentTrack,
            transportState: appState.playbackState.transportState
        )
    }
}
```

- [ ] **Step 4: Verify build**

```bash
xcodebuild -project /Users/denver/src/sonos/SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

- [ ] **Step 5: Commit**

```bash
git add SonoBar/Controllers/MediaKeyController.swift SonoBar/Services/AppState.swift SonoBar/AppDelegate.swift
git commit -m "feat: add media key support with MPRemoteCommandCenter"
```

---

### Task 11: Regenerate Xcode Project & Final Verification

**Files:**
- Modify: `project.yml` (if needed for new directories)

- [ ] **Step 1: Regenerate Xcode project to pick up new files**

```bash
cd /Users/denver/src/sonos && xcodegen generate
```

- [ ] **Step 2: Run SonoBarKit tests**

```bash
cd /Users/denver/src/sonos/SonoBarKit && bash test.sh
```

Expected: All tests pass (40 existing + new DIDLParser, ContentBrowser, AlarmScheduler, SleepTimerController tests).

- [ ] **Step 3: Build the app**

```bash
xcodebuild -project /Users/denver/src/sonos/SonoBar.xcodeproj -scheme SonoBar -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Launch and verify**

```bash
open /Users/denver/Library/Developer/Xcode/DerivedData/SonoBar-*/Build/Products/Debug/SonoBar.app
```

Verify:
- Browse tab shows Favorites grid, Playlists list, Queue list with segment switching
- Search filters content
- Alarms tab shows sleep timer buttons and alarm list
- Media keys work when popover is open

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: Phase 2 complete — Browse, Alarms, and Media Keys"
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | ContentItem model | 2 tests |
| 2 | DIDL-Lite parser | 4 tests |
| 3 | ContentBrowser service | 4 tests |
| 4 | SonosAlarm model | — |
| 5 | AlarmScheduler service | 3 tests |
| 6 | SleepTimerController | 5 tests |
| 7 | AppState additions | — |
| 8 | Browse view (3 files) | — |
| 9 | Alarms view (2 files) | — |
| 10 | MediaKeyController | — |
| 11 | Final verification | — |

**Total: 18 new unit tests across 11 tasks.**
