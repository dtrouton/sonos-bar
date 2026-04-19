import Testing
import Foundation
@testable import SonoBarKit

@Suite("AppleMusicCredentialsExtractor Tests")
struct AppleMusicCredentialsExtractorTests {

    /// Real DIDL snippet captured from the Task 0 spike — one Apple Music favorite.
    private static let favoriteDIDL = """
<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" \
xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
<item id="FV:2/44" parentID="FV:2" restricted="false">\
<dc:title>Dreaming of Bones</dc:title>\
<upnp:class>object.itemobject.item.sonos-favorite</upnp:class>\
<r:ordinal>2</r:ordinal>\
<res protocolInfo="x-rincon-cpcontainer:*:*:*">x-rincon-cpcontainer:1004206calbum%3A1649042949?sid=204&amp;flags=8300&amp;sn=19</res>\
<r:type>instantPlay</r:type>\
<r:description>Apple Music</r:description>\
<r:resMD>&lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item id=&quot;1004206calbum%3A1649042949&quot; parentID=&quot;1004206calbum%3A1649042949&quot; restricted=&quot;true&quot;&gt;&lt;dc:title&gt;Dreaming of Bones&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;&lt;desc id=&quot;cdudn&quot; nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;SA_RINCON52231_X_#Svc52231-890cb54f-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</r:resMD>\
</item>\
</DIDL-Lite>
"""

    /// Favorites with only non-Apple-Music entries.
    private static let nonAppleMusicFavoriteDIDL = """
<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" \
xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
<item id="FV:2/41" parentID="FV:2" restricted="false">\
<dc:title>Discover Sonos Radio</dc:title>\
<res></res>\
<r:description>Sonos Radio</r:description>\
</item>\
</DIDL-Lite>
"""

    /// A crafted DIDL where the accountToken contains non-hex chars; the extractor MUST reject it.
    private static let malformedTokenDIDL = """
<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" \
xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
<item id="FV:2/99" parentID="FV:2" restricted="false">\
<dc:title>Evil</dc:title>\
<res>x-rincon-cpcontainer:x?sid=204&amp;sn=19</res>\
<r:resMD>&lt;DIDL-Lite&gt;&lt;item&gt;&lt;desc id=&quot;cdudn&quot;&gt;SA_RINCON52231_X_#Svc52231-bad&amp;token-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;</r:resMD>\
</item>\
</DIDL-Lite>
"""

    @Test("Extracts sn=19 and token from real favorite DIDL")
    func extractsFromAppleMusicFavorite() {
        let creds = AppleMusicCredentialsExtractor.extract(favoritesDIDL: Self.favoriteDIDL)
        #expect(creds?.sn == 19)
        #expect(creds?.accountToken == "890cb54f")
    }

    @Test("Returns nil when no Apple Music favorites present")
    func nilOnNoAppleMusic() {
        let creds = AppleMusicCredentialsExtractor.extract(favoritesDIDL: Self.nonAppleMusicFavoriteDIDL)
        #expect(creds == nil)
    }

    @Test("Returns nil on empty DIDL")
    func nilOnEmpty() {
        #expect(AppleMusicCredentialsExtractor.extract(favoritesDIDL: "<DIDL-Lite></DIDL-Lite>") == nil)
    }

    @Test("Returns nil on malformed DIDL")
    func nilOnMalformed() {
        #expect(AppleMusicCredentialsExtractor.extract(favoritesDIDL: "not xml") == nil)
    }

    @Test("Rejects accountToken containing non-hex characters")
    func rejectsNonHexToken() {
        let creds = AppleMusicCredentialsExtractor.extract(favoritesDIDL: Self.malformedTokenDIDL)
        #expect(creds == nil)
    }
}
