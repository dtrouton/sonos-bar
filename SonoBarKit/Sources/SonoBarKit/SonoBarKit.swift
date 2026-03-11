// SonoBarKit
// Network and service layer for controlling Sonos speakers via UPnP/SOAP.

// Re-export Foundation so consumers (including test targets) get Foundation types
// without needing a separate import. This avoids a CommandLineTools-only build issue
// where `import Foundation` + `import Testing` requires _Testing_Foundation.framework.
@_exported import Foundation
