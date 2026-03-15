// SonoBar/Views/ContentGridView.swift
import SwiftUI
import SonoBarKit

struct ContentGridView: View {
    let items: [ContentItem]
    var onTap: (ContentItem) -> Void
    @Environment(AppState.self) private var appState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    Button { onTap(item) } label: {
                        VStack(spacing: 4) {
                            GridArtworkView(
                                albumArtURI: item.albumArtURI,
                                speakerIP: appState.deviceManager.activeDevice.flatMap {
                                    appState.deviceManager.coordinatorIP(for: $0.uuid)
                                }
                            )
                            Text(item.title)
                                .font(.system(size: 10))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

/// Loads and displays album art for a grid cell.
private struct GridArtworkView: View {
    let albumArtURI: String?
    let speakerIP: String?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: albumArtURI) {
            image = await loadImage()
        }
    }

    private func loadImage() async -> NSImage? {
        guard let artURI = albumArtURI, !artURI.isEmpty else { return nil }

        let urlString: String
        if artURI.hasPrefix("http://") || artURI.hasPrefix("https://") {
            urlString = artURI
        } else {
            guard let ip = speakerIP else { return nil }
            urlString = "http://\(ip):1400\(artURI)"
        }

        return await ArtworkCache.shared.image(for: urlString)
    }
}
