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
    /// Extracts metadata fields from the TrackMetaData DIDL-Lite XML.
    public init(from dict: [String: String]) {
        self.trackNumber = Int(dict["Track"] ?? "0") ?? 0
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
    /// Finds content between <tag> and </tag>.
    private static func extractTag(_ tag: String, from xml: String) -> String? {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"
        guard let openRange = xml.range(of: openTag),
              let closeRange = xml.range(of: closeTag, range: openRange.upperBound..<xml.endIndex) else {
            return nil
        }
        let value = String(xml[openRange.upperBound..<closeRange.lowerBound])
        return value.isEmpty ? nil : value
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
