// GroupTopology.swift
// SonoBarKit
//
// Zone group topology models and parser for Sonos multi-room grouping.

import Foundation

// MARK: - ZoneGroupMember

/// A member speaker in a Sonos zone group.
public struct ZoneGroupMember: Sendable, Equatable {
    public let uuid: String
    public let location: String
    public let zoneName: String
    public let ip: String

    public init(uuid: String, location: String, zoneName: String) {
        self.uuid = uuid
        self.location = location
        self.zoneName = zoneName
        // Extract IP from location URL (e.g., http://192.168.1.10:1400/xml/...)
        self.ip = ZoneGroupMember.extractIP(from: location)
    }

    private static func extractIP(from location: String) -> String {
        guard let url = URL(string: location), let host = url.host else {
            return ""
        }
        return host
    }
}

// MARK: - ZoneGroup

/// A group of Sonos speakers playing in sync.
public struct ZoneGroup: Sendable, Equatable {
    public let coordinatorUUID: String
    public let groupID: String
    public let members: [ZoneGroupMember]

    /// Whether this group has only one member (standalone speaker).
    public var isStandalone: Bool {
        members.count <= 1
    }

    public init(coordinatorUUID: String, groupID: String, members: [ZoneGroupMember]) {
        self.coordinatorUUID = coordinatorUUID
        self.groupID = groupID
        self.members = members
    }
}

// MARK: - ZoneGroupParser

/// Parses ZoneGroupState XML from Sonos devices into ZoneGroup models.
public enum ZoneGroupParser {

    /// Parses ZoneGroupState XML and returns an array of ZoneGroups.
    public static func parse(_ xml: String) throws -> [ZoneGroup] {
        guard let data = xml.data(using: .utf8) else {
            throw SOAPError(code: -1, message: "Failed to encode zone group XML as UTF-8")
        }
        let delegate = ZoneGroupXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? SOAPError(code: -1, message: "Zone group XML parse failed")
        }
        return delegate.groups
    }
}

// MARK: - ZoneGroupXMLDelegate

private final class ZoneGroupXMLDelegate: NSObject, XMLParserDelegate {
    var groups: [ZoneGroup] = []

    private var currentCoordinator: String = ""
    private var currentGroupID: String = ""
    private var currentMembers: [ZoneGroupMember] = []
    private var inZoneGroup = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "ZoneGroup":
            inZoneGroup = true
            currentCoordinator = attributeDict["Coordinator"] ?? ""
            currentGroupID = attributeDict["ID"] ?? ""
            currentMembers = []

        case "ZoneGroupMember":
            if inZoneGroup {
                let uuid = attributeDict["UUID"] ?? ""
                let location = attributeDict["Location"] ?? ""
                let zoneName = attributeDict["ZoneName"] ?? ""
                let member = ZoneGroupMember(uuid: uuid, location: location, zoneName: zoneName)
                currentMembers.append(member)
            }

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "ZoneGroup" {
            let group = ZoneGroup(
                coordinatorUUID: currentCoordinator,
                groupID: currentGroupID,
                members: currentMembers
            )
            groups.append(group)
            inZoneGroup = false
        }
    }
}
