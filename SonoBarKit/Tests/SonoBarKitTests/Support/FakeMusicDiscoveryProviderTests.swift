import Testing
import Foundation
@testable import SonoBarKit

@Suite("FakeMusicDiscoveryProvider Tests")
struct FakeMusicDiscoveryProviderTests {

    @Test("Returns scripted playlists")
    func returnsPlaylists() async throws {
        let fake = FakeMusicDiscoveryProvider()
        fake.playlists = [AppleMusicPlaylist(id: "p.1", name: "Mix", curatorName: nil,
                                             artworkURL: nil, trackCount: 3, isLibrary: true)]
        let result = try await fake.libraryPlaylists()
        #expect(result.count == 1)
        #expect(result[0].id == "p.1")
    }

    @Test("Throws scripted error")
    func throwsError() async {
        let fake = FakeMusicDiscoveryProvider()
        fake.errorToThrow = .networkError
        await #expect(throws: AppleMusicError.networkError) {
            _ = try await fake.search("x")
        }
    }
}
