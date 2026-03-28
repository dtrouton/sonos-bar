import Foundation

/// Discovers linked music services and their Sonos account serial numbers (sn)
/// by querying the MusicServices SOAP endpoint.
public enum MusicServiceDiscovery {

    /// Info about a linked music service on the Sonos system.
    public struct ServiceAccount: Sendable {
        public let sid: Int          // Service ID (e.g. 239 for Audible)
        public let name: String      // Human-readable name
        public let sn: Int           // Account serial number (0-indexed among authenticated services)
        public let serviceType: Int  // sid * 256 + 7
        public let authType: String  // "AppLink", "DeviceLink", "Anonymous"

        /// The CDUDN descriptor used in DIDL metadata for Sonos playback.
        public var cdudn: String {
            "SA_RINCON\(serviceType)_X_#Svc\(serviceType)-0-Token"
        }
    }

    /// Queries the Sonos speaker for all linked music services with their account serial numbers.
    public static func discoverServices(client: SOAPClient) async throws -> [ServiceAccount] {
        let result = try await client.callAction(
            service: .musicServices,
            action: "ListAvailableServices",
            params: []
        )

        guard let descriptorXML = result["AvailableServiceDescriptorList"],
              let typeListStr = result["AvailableServiceTypeList"] else {
            return []
        }

        // Parse the ordered list of active service types
        let activeTypes = typeListStr.split(separator: ",").map { String($0) }

        // Parse the service descriptor XML for name and auth info
        let serviceInfo = parseServiceDescriptors(descriptorXML)

        // Walk the type list in order, assigning sn to non-Anonymous services
        var accounts: [ServiceAccount] = []
        var authIndex = 0

        for typeStr in activeTypes {
            guard let typeInt = Int(typeStr) else { continue }
            let sid = (typeInt - 7) / 256

            guard let info = serviceInfo[sid] else { continue }

            if info.auth != "Anonymous" {
                accounts.append(ServiceAccount(
                    sid: sid,
                    name: info.name,
                    sn: authIndex,
                    serviceType: typeInt,
                    authType: info.auth
                ))
                authIndex += 1
            }
        }

        return accounts
    }

    /// Finds a specific service by ID (e.g. 239 for Audible, 204 for Apple Music).
    public static func findService(sid: Int, client: SOAPClient) async throws -> ServiceAccount? {
        let services = try await discoverServices(client: client)
        return services.first { $0.sid == sid }
    }

    // MARK: - Private

    struct ServiceInfo {
        let name: String
        let auth: String
    }

    private static func parseServiceDescriptors(_ xml: String) -> [Int: ServiceInfo] {
        guard let data = xml.data(using: .utf8) else { return [:] }

        let parser = ServiceDescriptorParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()

        return parser.services
    }
}

// MARK: - XML Parser

private final class ServiceDescriptorParser: NSObject, XMLParserDelegate {
    var services: [Int: MusicServiceDiscovery.ServiceInfo] = [:]
    private var currentSid: Int?
    private var currentName: String?
    private var currentAuth: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "Service" {
            currentSid = attributes["Id"].flatMap(Int.init)
            currentName = attributes["Name"]
        } else if elementName == "Policy" {
            currentAuth = attributes["Auth"]
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "Service", let sid = currentSid, let name = currentName {
            services[sid] = MusicServiceDiscovery.ServiceInfo(
                name: name,
                auth: currentAuth ?? "Anonymous"
            )
            currentSid = nil
            currentName = nil
            currentAuth = nil
        }
    }
}
