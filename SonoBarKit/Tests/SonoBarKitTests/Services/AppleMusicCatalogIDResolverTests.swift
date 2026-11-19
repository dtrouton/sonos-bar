import Testing
import Foundation
@testable import SonoBarKit

@Suite("AppleMusicCatalogIDResolver Tests")
struct AppleMusicCatalogIDResolverTests {

    @Test("Catalog song: id is already the catalog id")
    func catalogSong() {
        let json = #"{"id":"1422700837","kind":"song","isLibrary":false}"#
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data(json.utf8)) == "1422700837")
    }

    @Test("Library song with catalogId field resolves to catalog id")
    func librarySongWithCatalogId() {
        let json = #"{"id":"i.abc123","kind":"song","isLibrary":true,"catalogId":"1422700837"}"#
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data(json.utf8)) == "1422700837")
    }

    @Test("Library playlist resolves to its pl. catalog id (real MusicKit shape)")
    func libraryPlaylistCatalogId() {
        // Exact playParameters shape captured from a live MusicKit library playlist ("Stories").
        // The numeric `id` is a persistent id Sonos rejects; the catalogId is the playable one.
        let json = #"{"musicKit_databaseID":"954D256EA2D794F3","kind":"playlist","catalogId":"pl.u-kv9l2M5C7PK66p8","isLibrary":true,"id":"2910742593404547372","musicKit_persistentID":"2910742593404547372"}"#
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data(json.utf8)) == "pl.u-kv9l2M5C7PK66p8")
    }

    @Test("Library playlist with no catalogId is not playable on Sonos")
    func libraryPlaylistNoCatalogId() {
        let json = #"{"kind":"playlist","isLibrary":true,"musicKit_persistentID":"7929476746859573702","id":"7929476746859573702"}"#
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data(json.utf8)) == nil)
    }

    @Test("Library-only song without catalogId is not playable")
    func libraryOnlySong() {
        let json = #"{"id":"i.abc123","kind":"song","isLibrary":true}"#
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data(json.utf8)) == nil)
    }

    @Test("Malformed JSON returns nil")
    func malformed() {
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data("not json".utf8)) == nil)
    }

    @Test("Nil input returns nil")
    func nilInput() {
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: nil) == nil)
    }

    @Test("Catalog song with isLibrary absent still resolves via numeric id")
    func catalogSongNoIsLibraryField() {
        let json = #"{"id":"1422700837","kind":"song"}"#
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data(json.utf8)) == "1422700837")
    }

    @Test("Empty catalogId on a library item is not playable")
    func emptyCatalogIdLibrary() {
        let json = #"{"id":"i.abc123","kind":"song","isLibrary":true,"catalogId":""}"#
        #expect(AppleMusicCatalogIDResolver.catalogID(playParametersJSON: Data(json.utf8)) == nil)
    }
}
