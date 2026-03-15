// PlaybackState.swift
// SonoBarKit
//
// Transport state, track info, and playback state models for Sonos speakers.

// MARK: - TransportState

/// The current transport state of a Sonos speaker.
public enum TransportState: String, Sendable, Equatable {
    case playing = "PLAYING"
    case pausedPlayback = "PAUSED_PLAYBACK"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
    case noMediaPresent = "NO_MEDIA_PRESENT"
}

// MARK: - TrackInfo

/// Information about the currently playing track.
public struct TrackInfo: Sendable, Equatable {
    public let trackNumber: Int
    public let duration: String
    public let elapsed: String
    public let uri: String
    public let title: String?
    public let artist: String?
    public let album: String?
    public let albumArtURI: String?

    public init(
        trackNumber: Int,
        duration: String,
        elapsed: String,
        uri: String,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtURI: String? = nil
    ) {
        self.trackNumber = trackNumber
        self.duration = duration
        self.elapsed = elapsed
        self.uri = uri
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtURI = albumArtURI
    }

    /// Creates a TrackInfo from a position info response dictionary.
    /// Returns nil if the response has no Track field.
    /// Extracts metadata fields from the TrackMetaData DIDL-Lite XML.
    public init?(fromPositionInfo dict: [String: String]) {
        guard let trackStr = dict["Track"], let num = Int(trackStr) else { return nil }
        self.trackNumber = num
        self.duration = dict["TrackDuration"] ?? "0:00:00"
        self.elapsed = dict["RelTime"] ?? "0:00:00"
        self.uri = dict["TrackURI"] ?? ""

        // Parse metadata from DIDL-Lite XML using simple tag extraction
        let metadata = dict["TrackMetaData"] ?? ""
        self.title = TrackInfo.extractTag("dc:title", from: metadata)
        self.artist = TrackInfo.extractTag("dc:creator", from: metadata)
        self.album = TrackInfo.extractTag("upnp:album", from: metadata)
        self.albumArtURI = TrackInfo.extractTag("upnp:albumArtURI", from: metadata)
    }

    /// Simple tag content extraction from XML.
    /// Handles both `<tag>` and `<tag attr="...">` forms.
    /// Decodes XML entities in the extracted value.
    private static func extractTag(_ tag: String, from xml: String) -> String? {
        let searchTag = "<\(tag)"
        var searchStart = xml.startIndex
        // Walk forward to find an exact tag match (not a prefix, e.g. <upnp:album vs <upnp:albumArtURI)
        while let openRange = xml.range(of: searchTag, range: searchStart..<xml.endIndex) {
            let afterTag = openRange.upperBound
            guard afterTag < xml.endIndex else { return nil }
            let next = xml[afterTag]
            // Valid tag boundary: '>' (no attrs), ' '/'\t' (attrs), or '/' (self-closing)
            if next == ">" || next == " " || next == "\t" || next == "/" {
                guard let gtRange = xml.range(of: ">", range: afterTag..<xml.endIndex),
                      let closeRange = xml.range(of: "</\(tag)>", range: gtRange.upperBound..<xml.endIndex) else {
                    return nil
                }
                let raw = String(xml[gtRange.upperBound..<closeRange.lowerBound])
                guard !raw.isEmpty else { return nil }
                return decodeXMLEntities(raw)
            }
            searchStart = openRange.upperBound
        }
        return nil
    }

    /// Decodes standard XML entities.
    private static func decodeXMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

// MARK: - PlaybackState

/// Aggregated playback state for a Sonos speaker.
public struct PlaybackState: Sendable, Equatable {
    public let transportState: TransportState
    public let volume: Int
    public let isMuted: Bool
    public let currentTrack: TrackInfo?

    public init(
        transportState: TransportState,
        volume: Int,
        isMuted: Bool,
        currentTrack: TrackInfo? = nil
    ) {
        self.transportState = transportState
        self.volume = volume
        self.isMuted = isMuted
        self.currentTrack = currentTrack
    }
}
