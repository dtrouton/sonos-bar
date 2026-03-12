import Foundation

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
