// SonoBar/Views/PlexAlbumListView.swift
import SwiftUI
import SonoBarKit

struct PlexAlbumListView: View {
    let libraryTitle: String
    let albums: [PlexAlbum]
    let isLoading: Bool
    var onTap: (PlexAlbum) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && albums.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading \(libraryTitle)...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if albums.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No items found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(albums) { album in
                            Button { onTap(album) } label: {
                                VStack(spacing: 4) {
                                    PlexArtworkView(thumbPath: album.thumbPath)
                                    Text(album.title)
                                        .font(.system(size: 10))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                    Text(album.artist)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }
}
