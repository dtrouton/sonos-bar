import Testing
@testable import SonoBarKit

@Suite("Model Tests")
struct ModelTests {

    @Test func testSonosDeviceCreation() {
        let device = SonosDevice(
            uuid: "RINCON_48A6B88A7E4E01400",
            ip: "192.168.1.42",
            roomName: "Living Room",
            modelName: "Sonos One"
        )

        #expect(device.uuid == "RINCON_48A6B88A7E4E01400")
        #expect(device.ip == "192.168.1.42")
        #expect(device.roomName == "Living Room")
        #expect(device.modelName == "Sonos One")
        #expect(device.isReachable == true)
        #expect(device.id == device.uuid)

        let device2 = SonosDevice(
            uuid: "RINCON_48A6B88A7E4E01400",
            ip: "192.168.1.42",
            roomName: "Living Room",
            modelName: "Sonos One",
            isReachable: false
        )
        #expect(device2.isReachable == false)
        #expect(device == device2.with(isReachable: true))
    }

    @Test func testTransportStateFromString() {
        #expect(TransportState(rawValue: "PLAYING") == .playing)
        #expect(TransportState(rawValue: "PAUSED_PLAYBACK") == .pausedPlayback)
        #expect(TransportState(rawValue: "STOPPED") == .stopped)
        #expect(TransportState(rawValue: "TRANSITIONING") == .transitioning)
        #expect(TransportState(rawValue: "INVALID") == nil)
    }

    @Test func testTrackInfoFromPositionResponse() {
        let positionDict: [String: String] = [
            "Track": "3",
            "TrackDuration": "0:04:30",
            "RelTime": "0:01:15",
            "TrackURI": "x-sonos-spotify:spotify:track:abc123",
            "TrackMetaData": """
            <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
            <item>
            <dc:title>My Song</dc:title>
            <dc:creator>Test Artist</dc:creator>
            <upnp:album>Test Album</upnp:album>
            <upnp:albumArtURI>http://example.com/art.jpg</upnp:albumArtURI>
            </item>
            </DIDL-Lite>
            """
        ]

        let trackInfo = TrackInfo(from: positionDict)
        #expect(trackInfo.trackNumber == 3)
        #expect(trackInfo.duration == "0:04:30")
        #expect(trackInfo.elapsed == "0:01:15")
        #expect(trackInfo.uri == "x-sonos-spotify:spotify:track:abc123")
        #expect(trackInfo.title == "My Song")
        #expect(trackInfo.artist == "Test Artist")
        #expect(trackInfo.album == "Test Album")
        #expect(trackInfo.albumArtURI == "http://example.com/art.jpg")
    }

    @Test func testParseZoneGroupState() throws {
        let xml = """
        <ZoneGroupState>
          <ZoneGroups>
            <ZoneGroup Coordinator="RINCON_AAA" ID="group1">
              <ZoneGroupMember UUID="RINCON_AAA" Location="http://192.168.1.10:1400/xml/device_description.xml" ZoneName="Kitchen"/>
              <ZoneGroupMember UUID="RINCON_BBB" Location="http://192.168.1.11:1400/xml/device_description.xml" ZoneName="Dining Room"/>
            </ZoneGroup>
            <ZoneGroup Coordinator="RINCON_CCC" ID="group2">
              <ZoneGroupMember UUID="RINCON_CCC" Location="http://192.168.1.12:1400/xml/device_description.xml" ZoneName="Bedroom"/>
            </ZoneGroup>
          </ZoneGroups>
        </ZoneGroupState>
        """

        let groups = try ZoneGroupParser.parse(xml)
        #expect(groups.count == 2)

        let group1 = try #require(groups.first { $0.groupID == "group1" })
        #expect(group1.coordinatorUUID == "RINCON_AAA")
        #expect(group1.members.count == 2)
        #expect(group1.isStandalone == false)

        let kitchen = try #require(group1.members.first { $0.uuid == "RINCON_AAA" })
        #expect(kitchen.zoneName == "Kitchen")
        #expect(kitchen.ip == "192.168.1.10")
        #expect(kitchen.location == "http://192.168.1.10:1400/xml/device_description.xml")

        let dining = try #require(group1.members.first { $0.uuid == "RINCON_BBB" })
        #expect(dining.zoneName == "Dining Room")
        #expect(dining.ip == "192.168.1.11")

        let group2 = try #require(groups.first { $0.groupID == "group2" })
        #expect(group2.coordinatorUUID == "RINCON_CCC")
        #expect(group2.members.count == 1)
        #expect(group2.isStandalone == true)

        let bedroom = try #require(group2.members.first)
        #expect(bedroom.zoneName == "Bedroom")
        #expect(bedroom.ip == "192.168.1.12")
    }
}
