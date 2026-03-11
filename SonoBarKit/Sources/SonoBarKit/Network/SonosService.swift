// SonosService.swift
// SonoBarKit
//
// Enumerates all Sonos UPnP service endpoints used for SOAP control and eventing.

public enum SonosService: String, CaseIterable, Sendable {
    case avTransport
    case renderingControl
    case groupRenderingControl
    case zoneGroupTopology
    case contentDirectory
    case alarmClock
    case deviceProperties

    /// The UPnP control URL path (relative to device base URL)
    public var controlURL: String {
        switch self {
        case .avTransport:
            return "/MediaRenderer/AVTransport/Control"
        case .renderingControl:
            return "/MediaRenderer/RenderingControl/Control"
        case .groupRenderingControl:
            return "/MediaRenderer/GroupRenderingControl/Control"
        case .zoneGroupTopology:
            return "/ZoneGroupTopology/Control"
        case .contentDirectory:
            return "/MediaServer/ContentDirectory/Control"
        case .alarmClock:
            return "/AlarmClock/Control"
        case .deviceProperties:
            return "/DeviceProperties/Control"
        }
    }

    /// The UPnP event subscription URL path (relative to device base URL)
    public var eventURL: String {
        switch self {
        case .avTransport:
            return "/MediaRenderer/AVTransport/Event"
        case .renderingControl:
            return "/MediaRenderer/RenderingControl/Event"
        case .groupRenderingControl:
            return "/MediaRenderer/GroupRenderingControl/Event"
        case .zoneGroupTopology:
            return "/ZoneGroupTopology/Event"
        case .contentDirectory:
            return "/MediaServer/ContentDirectory/Event"
        case .alarmClock:
            return "/AlarmClock/Event"
        case .deviceProperties:
            return "/DeviceProperties/Event"
        }
    }

    /// The full UPnP service type URN
    public var serviceType: String {
        switch self {
        case .avTransport:
            return "urn:schemas-upnp-org:service:AVTransport:1"
        case .renderingControl:
            return "urn:schemas-upnp-org:service:RenderingControl:1"
        case .groupRenderingControl:
            return "urn:schemas-upnp-org:service:GroupRenderingControl:1"
        case .zoneGroupTopology:
            return "urn:schemas-upnp-org:service:ZoneGroupTopology:1"
        case .contentDirectory:
            return "urn:schemas-upnp-org:service:ContentDirectory:1"
        case .alarmClock:
            return "urn:schemas-upnp-org:service:AlarmClock:1"
        case .deviceProperties:
            return "urn:schemas-upnp-org:service:DeviceProperties:1"
        }
    }
}
