// XMLResponseParser.swift
// SonoBarKit
//
// Parses SOAP XML responses and UPnP event notifications from Sonos devices.

import Foundation

// MARK: - SOAPError

/// An error returned by a Sonos device in a SOAP Fault envelope.
public struct SOAPError: Error, Sendable {
    /// The UPnP error code (e.g. 701 = Transition Not Available)
    public let code: Int
    /// Human-readable fault string from the device
    public let description: String

    public init(code: Int, description: String = "") {
        self.code = code
        self.description = description
    }
}

// MARK: - XMLResponseParser

/// Parses SOAP XML responses and UPnP event bodies from Sonos devices.
public enum XMLResponseParser {

    // MARK: - Public API

    /// Parses a SOAP response envelope and returns a flat dictionary of element name → text content.
    ///
    /// Extracts the child elements of the first `*Response` element inside `s:Body`.
    /// Throws `SOAPError` if the body contains a `s:Fault` element.
    public static func parse(_ xml: String) throws -> [String: String] {
        guard let data = xml.data(using: .utf8) else {
            throw SOAPError(code: -1, description: "Failed to encode XML as UTF-8")
        }
        let delegate = SOAPResponseDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        if let fault = delegate.fault {
            throw fault
        }
        return delegate.result
    }

    /// Parses a UPnP event property set body.
    ///
    /// Extracts the HTML-encoded `LastChange` inner XML and returns a flat dictionary
    /// of attribute name → val for each child element of the first `InstanceID` element.
    public static func parseEventBody(_ xml: String) throws -> [String: String] {
        guard let data = xml.data(using: .utf8) else {
            throw SOAPError(code: -1, description: "Failed to encode event XML as UTF-8")
        }
        // Step 1: extract the raw LastChange text from the property set
        let propDelegate = EventPropertyDelegate()
        let propParser = XMLParser(data: data)
        propParser.delegate = propDelegate
        propParser.parse()

        guard let lastChangeXML = propDelegate.lastChangeValue, !lastChangeXML.isEmpty else {
            return [:]
        }

        // Step 2: parse the inner (HTML-decoded) LastChange XML
        guard let innerData = lastChangeXML.data(using: .utf8) else {
            throw SOAPError(code: -1, description: "Failed to encode LastChange XML as UTF-8")
        }
        let lcDelegate = LastChangeDelegate()
        let lcParser = XMLParser(data: innerData)
        lcParser.delegate = lcDelegate
        lcParser.parse()

        return lcDelegate.result
    }
}

// MARK: - SOAPResponseDelegate

/// Parses a SOAP envelope, extracting child elements of the `*Response` element.
/// Also detects `s:Fault` and surfaces it as a `SOAPError`.
private final class SOAPResponseDelegate: NSObject, XMLParserDelegate {
    var result: [String: String] = [:]
    var fault: SOAPError?

    // depth tracking
    private var depth = 0
    private var inBody = false
    private var inResponseElement = false
    private var responseElementDepth = 0
    private var inFault = false
    private var inErrorCode = false
    private var inFaultString = false

    private var currentElement = ""
    private var currentText = ""
    private var errorCode = 0
    private var faultString = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        let localName = localPart(of: elementName)
        currentElement = localName
        currentText = ""

        if localName == "Body" {
            inBody = true
            return
        }

        if inBody && !inResponseElement && !inFault {
            if localName == "Fault" {
                inFault = true
                return
            }
            // Any other element directly in Body is our Response element
            if depth == 3 { // Envelope(1) > Body(2) > ResponseElement(3)
                inResponseElement = true
                responseElementDepth = depth
            }
        }

        if inFault && localName == "errorCode" {
            inErrorCode = true
        }
        if inFault && localName == "faultstring" {
            inFaultString = true
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
        let localName = localPart(of: elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inResponseElement && depth > responseElementDepth {
            // Child element of the Response element — capture its text
            result[localName] = text
        }

        if inErrorCode && localName == "errorCode" {
            errorCode = Int(text) ?? 0
            inErrorCode = false
        }
        if inFaultString && localName == "faultstring" {
            faultString = text
            inFaultString = false
        }

        if inResponseElement && depth == responseElementDepth {
            inResponseElement = false
        }
        if inFault && localName == "Fault" {
            fault = SOAPError(code: errorCode, description: faultString)
            inFault = false
        }
        if localName == "Body" {
            inBody = false
        }

        currentText = ""
        depth -= 1
    }
}

// MARK: - EventPropertyDelegate

/// Parses a UPnP `e:propertyset` document and extracts the raw text of `LastChange`.
private final class EventPropertyDelegate: NSObject, XMLParserDelegate {
    var lastChangeValue: String?

    private var inLastChange = false
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = localPart(of: elementName)
        if localName == "LastChange" {
            inLastChange = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inLastChange {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = localPart(of: elementName)
        if localName == "LastChange" {
            lastChangeValue = currentText
            inLastChange = false
        }
    }
}

// MARK: - LastChangeDelegate

/// Parses the inner XML from a UPnP LastChange value.
/// Extracts `val` attributes from children of the `InstanceID` element.
private final class LastChangeDelegate: NSObject, XMLParserDelegate {
    var result: [String: String] = [:]

    private var inInstanceID = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = localPart(of: elementName)

        if localName == "InstanceID" {
            inInstanceID = true
            return
        }

        if inInstanceID, let val = attributeDict["val"] {
            result[localName] = val
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = localPart(of: elementName)
        if localName == "InstanceID" {
            inInstanceID = false
        }
    }
}

// MARK: - Helpers

/// Strips namespace prefix from qualified XML element name (e.g. "s:Body" → "Body").
private func localPart(of elementName: String) -> String {
    if let colonIndex = elementName.firstIndex(of: ":") {
        return String(elementName[elementName.index(after: colonIndex)...])
    }
    return elementName
}
