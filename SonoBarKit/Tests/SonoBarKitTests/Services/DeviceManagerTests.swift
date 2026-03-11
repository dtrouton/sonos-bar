import Testing
@testable import SonoBarKit

@Suite("DeviceManager Tests")
struct DeviceManagerTests {

    private let zoneGroupXML = """
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

    @Test func testUpdateDevicesFromZoneGroupState() throws {
        let manager = DeviceManager()
        try manager.updateFromZoneGroupState(zoneGroupXML)

        #expect(manager.devices.count == 3)
        #expect(manager.groups.count == 2)

        let kitchen = manager.devices.first { $0.uuid == "RINCON_AAA" }
        #expect(kitchen != nil)
        #expect(kitchen?.roomName == "Kitchen")
        #expect(kitchen?.ip == "192.168.1.10")

        let bedroom = manager.devices.first { $0.uuid == "RINCON_CCC" }
        #expect(bedroom != nil)
        #expect(bedroom?.roomName == "Bedroom")
        #expect(bedroom?.ip == "192.168.1.12")
    }

    @Test func testCoordinatorForDevice() throws {
        let manager = DeviceManager()
        try manager.updateFromZoneGroupState(zoneGroupXML)

        // RINCON_BBB is a member of group1, coordinated by RINCON_AAA at 192.168.1.10
        let coordinatorIP = manager.coordinatorIP(for: "RINCON_BBB")
        #expect(coordinatorIP == "192.168.1.10")

        // RINCON_CCC is its own coordinator
        let selfCoordinatorIP = manager.coordinatorIP(for: "RINCON_CCC")
        #expect(selfCoordinatorIP == "192.168.1.12")

        // Unknown device returns nil
        let unknownIP = manager.coordinatorIP(for: "RINCON_UNKNOWN")
        #expect(unknownIP == nil)
    }

    @Test func testActiveDevicePersistsAcrossUpdates() throws {
        let manager = DeviceManager()
        try manager.updateFromZoneGroupState(zoneGroupXML)

        manager.setActiveDevice(uuid: "RINCON_BBB")
        #expect(manager.activeDevice?.uuid == "RINCON_BBB")
        #expect(manager.activeDevice?.roomName == "Dining Room")

        // Update with same data - active device should persist
        try manager.updateFromZoneGroupState(zoneGroupXML)
        #expect(manager.activeDevice?.uuid == "RINCON_BBB")
        #expect(manager.activeDevice?.roomName == "Dining Room")

        // Check group and coordinator queries
        let group = manager.group(for: "RINCON_BBB")
        #expect(group?.groupID == "group1")
        #expect(manager.isCoordinator("RINCON_AAA") == true)
        #expect(manager.isCoordinator("RINCON_BBB") == false)
    }
}
