// SonoBar/Views/AudibleBrowseView.swift
import SwiftUI
import SonoBarKit

struct AudibleBrowseView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    /// Simple navigation stack: each entry describes a pushed view.
    enum AudibleNav: Equatable {
        case chapterList(AudibleBook)

        static func == (lhs: AudibleNav, rhs: AudibleNav) -> Bool {
            switch (lhs, rhs) {
            case (.chapterList(let a), .chapterList(let b)):
                return a.asin == b.asin
            }
        }
    }

    @State private var navigationPath: [AudibleNav] = []

    var body: some View {
        if appState.audibleClient == nil {
            AudibleSetupView()
        } else if appState.sonosAudibleParams == nil {
            paramsNeededView
        } else {
            VStack(spacing: 0) {
                // Search bar — always visible
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search Audible", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

                // Back button when navigated deeper
                if !navigationPath.isEmpty && searchText.isEmpty {
                    HStack(spacing: 4) {
                        Button {
                            navigationPath.removeLast()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11))
                                Text("Back")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }

                if !searchText.isEmpty {
                    // Search results
                    let results = appState.searchAudibleBooks(query: searchText)
                    bookGrid(books: results)
                } else {
                    // Show current level
                    switch navigationPath.last {
                    case .chapterList(let book):
                        AudibleChapterView(book: book)

                    case nil:
                        audibleHome
                    }
                }
            }
            .onAppear {
                Task {
                    await appState.loadAudibleLibrary()
                    await appState.loadAudibleOnDeck()
                }
            }
        }
    }

    // MARK: - Params Needed View

    private var paramsNeededView: some View {
        VStack(spacing: 12) {
            Image(systemName: "headphones")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("Play any Audible book from the Sonos app once, then try again here")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Button("Retry") {
                Task { await appState.refreshAllRooms() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Audible Home

    private var audibleHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Continue Listening section
                if !appState.audibleOnDeck.isEmpty {
                    Text("Continue Listening")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)

                    LazyVStack(spacing: 0) {
                        ForEach(appState.audibleOnDeck, id: \.book.asin) { item in
                            Button {
                                Task {
                                    await appState.playAudibleBook(
                                        book: item.book,
                                        seekOffsetMs: item.positionMs
                                    )
                                }
                            } label: {
                                onDeckRow(book: item.book, positionMs: item.positionMs)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Library section
                if !appState.audibleBooks.isEmpty {
                    Text("Library")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)

                    bookGrid(books: appState.audibleBooks)
                }

                // Loading state
                if appState.isAudibleLoading && appState.audibleBooks.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading library...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                }

                // Error display
                if let error = appState.audibleError {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 11))
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                        HStack(spacing: 8) {
                            Button("Retry") {
                                Task {
                                    await appState.loadAudibleLibrary()
                                    await appState.loadAudibleOnDeck()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button("Disconnect") {
                                appState.disconnectAudible()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Book Grid

    private func bookGrid(books: [AudibleBook]) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(books) { book in
                    Button {
                        searchText = ""
                        Task { await appState.loadAudibleChapters(asin: book.asin) }
                        navigationPath.append(.chapterList(book))
                    } label: {
                        VStack(spacing: 4) {
                            AudibleArtworkView(coverURL: book.coverURL)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            Text(book.title)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Text(book.author)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - On Deck Row

    private func onDeckRow(book: AudibleBook, positionMs: Int) -> some View {
        HStack(spacing: 10) {
            AudibleArtworkView(coverURL: book.coverURL)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(book.author)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                let progressPct = book.durationMs > 0
                    ? Int(Double(positionMs) / Double(book.durationMs) * 100)
                    : 0
                let remainingMin = max(0, (book.durationMs - positionMs) / 60_000)
                Text("\(progressPct)% \u{00B7} \(remainingMin)m left")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "play.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - AudibleArtworkView

/// Loads and displays Audible cover art from an absolute URL.
struct AudibleArtworkView: View {
    let coverURL: String?
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
                        Image(systemName: "book")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: coverURL) {
            image = await loadImage()
        }
    }

    private func loadImage() async -> NSImage? {
        guard let coverURL, !coverURL.isEmpty else { return nil }
        return await ArtworkCache.shared.image(for: coverURL)
    }
}
