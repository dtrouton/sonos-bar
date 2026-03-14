// SonoBar/Views/QueueListView.swift
import SwiftUI
import SonoBarKit

struct QueueListView: View {
    let items: [ContentItem]
    var currentTrackURI: String?
    var onTap: (ContentItem) -> Void

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                Text("Queue is empty")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        Button { onTap(item) } label: {
                            HStack(spacing: 8) {
                                if item.resourceURI == currentTrackURI {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 14)
                                } else {
                                    Text("")
                                        .frame(width: 14)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    if let desc = item.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                item.resourceURI == currentTrackURI
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
