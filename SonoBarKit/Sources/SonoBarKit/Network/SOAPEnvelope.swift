// SOAPEnvelope.swift
// SonoBarKit
//
// Builds SOAP XML envelopes and SOAPACTION headers for Sonos UPnP requests.

public enum SOAPEnvelope {

    // MARK: - Build (Dictionary overload — keys sorted for determinism)

    /// Builds a SOAP envelope XML string from a [String: String] dictionary.
    /// Keys are sorted alphabetically for deterministic output.
    public static func build(
        service: SonosService,
        action: String,
        params: [String: String]
    ) -> String {
        let orderedParams = params.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        return build(service: service, action: action, orderedParams: orderedParams)
    }

    // MARK: - Build (ordered tuples overload — preserves order)

    /// Builds a SOAP envelope XML string from an ordered array of (key, value) tuples.
    /// Use this overload when parameter order matters for the Sonos device.
    public static func build(
        service: SonosService,
        action: String,
        params: [(String, String)]
    ) -> String {
        return build(service: service, action: action, orderedParams: params)
    }

    // MARK: - SOAPACTION header

    /// Returns the value for the `SOAPACTION` HTTP header.
    /// Format: `"<serviceType>#<action>"`
    public static func soapActionHeader(service: SonosService, action: String) -> String {
        return "\"\(service.serviceType)#\(action)\""
    }

    // MARK: - Private core builder

    private static func build(
        service: SonosService,
        action: String,
        orderedParams: [(String, String)]
    ) -> String {
        let paramXML = orderedParams
            .map { "<\($0.0)>\($0.1)</\($0.0)>" }
            .joined(separator: "\n      ")

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action) xmlns:u="\(service.serviceType)">
              \(paramXML)
            </u:\(action)>
          </s:Body>
        </s:Envelope>
        """
    }
}
