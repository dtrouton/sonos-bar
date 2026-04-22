// AppleMusicURIs.swift
// SonoBarKit
//
// Pure URI and DIDL metadata construction for Apple Music playback on Sonos.
// URI templates and account-token format verified against a live speaker in the
// Task 0 spike; see docs/superpowers/notes/2026-04-19-apple-music-smapi-spike.md.

import Foundation

public enum AppleMusicURIs {

    public static let serviceID = 204
    public static let serviceType = 52231   // serviceID * 256 + 7

    public static func trackURI(id: String, sn: Int) -> String {
        "x-sonos-http:song%3a\(id).mp4?sid=\(serviceID)&flags=8224&sn=\(sn)"
    }

    public static func albumContainerURI(id: String) -> String {
        "x-rincon-cpcontainer:1004206calbum%3a\(id)"
    }

    public static func didl(for item: AppleMusicPlayable,
                            credentials: AppleMusicCredentials) -> String {
        let title = xmlEscape(item.title)
        let upnpClass = upnpClass(for: item)
        let itemID = itemID(for: item)
        let parentID = parentID(for: item)
        let artTag = item.artworkURL.map {
            "<upnp:albumArtURI>\(xmlEscape($0.absoluteString))</upnp:albumArtURI>"
        } ?? ""
        let desc = "SA_RINCON\(serviceType)_X_#Svc\(serviceType)-\(credentials.accountToken)-Token"

        return """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="\(itemID)" parentID="\(parentID)" restricted="true">\
        <dc:title>\(title)</dc:title>\
        <upnp:class>\(upnpClass)</upnp:class>\
        <desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">\(desc)</desc>\
        \(artTag)\
        </item></DIDL-Lite>
        """
    }

    private static func upnpClass(for item: AppleMusicPlayable) -> String {
        switch item {
        case .track: return "object.item.audioItem.musicTrack"
        case .album: return "object.container.album.musicAlbum"
        }
    }

    private static func itemID(for item: AppleMusicPlayable) -> String {
        switch item {
        case .track(let t): return "10032028song%3a\(t.id)"
        case .album(let a): return "1004206calbum%3a\(a.id)"
        }
    }

    private static func parentID(for item: AppleMusicPlayable) -> String {
        switch item {
        case .track: return "00020000song:"
        case .album: return "00020000album:"
        }
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
