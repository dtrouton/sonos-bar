// SonoBar/Views/ContentListView.swift
import SwiftUI
import SonoBarKit

struct ContentListView: View {
    let items: [ContentItem]
    var currentTrackURI: String?
    var onTap: (ContentItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(items) { item in
                    Button { onTap(item) } label: {
                        HStack(spacing: 10) {
                            if item.resourceURI == currentTrackURI {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 16)
                            } else {
                                Color.clear.frame(width: 16, height: 1)
                            }

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: item.isContainer ? "music.note.list" : "music.note")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                if let desc = item.description {
                                    Text(desc)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
