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
