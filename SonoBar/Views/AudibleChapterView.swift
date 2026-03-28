// SonoBar/Views/AudibleChapterView.swift
import SwiftUI
import SonoBarKit

struct AudibleChapterView: View {
    @Environment(AppState.self) private var appState
    let book: AudibleBook

    /// The listening position for this book, looked up from on-deck data.
    private var positionMs: Int? {
        appState.audibleOnDeck.first(where: { $0.book.asin == book.asin })?.positionMs
    }

    /// Index of the chapter that contains the current listening position.
    private var inProgressChapterIndex: Int? {
        guard let pos = positionMs else { return nil }
        return appState.audibleChapters.firstIndex { chapter in
            pos >= chapter.startOffsetMs && pos < chapter.startOffsetMs + chapter.durationMs
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.isAudibleLoading && appState.audibleChapters.isEmpty && appState.audibleEpisodes.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(book.isPodcast ? "Loading episodes..." : "Loading chapters...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if book.isPodcast {
                podcastContent
            } else {
                bookContent
            }

            // Error display
            if let error = appState.audibleError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .onAppear {
            if book.isPodcast {
                Task { await appState.loadAudibleEpisodes(parentAsin: book.asin) }
            } else {
                Task { await appState.loadAudibleChapters(asin: book.asin) }
            }
        }
    }

    // MARK: - Book Content (Chapters)

    private var bookContent: some View {
        Group {
            if appState.audibleChapters.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No chapters found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        bookHeader

                        // Resume / Play All buttons
                        HStack(spacing: 8) {
                            playAllButton
                            resumeButton
                        }
                        .padding(.bottom, 8)

                        // Chapter list
                        LazyVStack(spacing: 0) {
                            ForEach(appState.audibleChapters) { chapter in
                                Button {
                                    Task {
                                        await appState.playAudibleChapter(
                                            book: book,
                                            chapter: chapter
                                        )
                                    }
                                } label: {
                                    chapterRow(chapter: chapter)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Podcast Content (Episodes)

    private var podcastContent: some View {
        Group {
            if appState.audibleEpisodes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No episodes found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        bookHeader

                        Text("\(appState.audibleEpisodes.count) episodes")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)

                        // Episode list
                        LazyVStack(spacing: 0) {
                            ForEach(appState.audibleEpisodes) { episode in
                                Button {
                                    Task {
                                        await appState.playAudibleBook(book: episode)
                                    }
                                } label: {
                                    episodeRow(episode: episode)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared Header

    private var bookHeader: some View {
        VStack(spacing: 8) {
            AudibleArtworkView(coverURL: book.coverURL)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(book.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(book.author)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if book.durationMs > 0 {
                Text(formatTotalDuration(book.durationMs))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Buttons

    private var playAllButton: some View {
        Button {
            Task {
                await appState.playAudibleBook(book: book)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                Text("Play All")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.15))
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resumeButton: some View {
        if let pos = positionMs, pos > 0 {
            Button {
                Task {
                    await appState.playAudibleBook(
                        book: book,
                        seekOffsetMs: pos
                    )
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                    Text("Resume")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Chapter Row

    private func chapterRow(chapter: AudibleChapter) -> some View {
        HStack(spacing: 8) {
            Text("\(chapter.index + 1)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                if let pos = positionMs, let inProgressIdx = inProgressChapterIndex,
                   chapter.index == appState.audibleChapters[inProgressIdx].index {
                    let chapterProgress = Double(pos - chapter.startOffsetMs) / Double(chapter.durationMs)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.accentColor)
                                .frame(
                                    width: geo.size.width * min(1, max(0, CGFloat(chapterProgress))),
                                    height: 3
                                )
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer()

            Text(formatDuration(chapter.durationMs))
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Episode Row

    private func episodeRow(episode: AudibleBook) -> some View {
        HStack(spacing: 10) {
            AudibleArtworkView(coverURL: episode.coverURL ?? book.coverURL)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)

                if episode.durationMs > 0 {
                    Text(formatTotalDuration(episode.durationMs))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "play.fill")
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func formatTotalDuration(_ ms: Int) -> String {
        let totalMinutes = ms / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
