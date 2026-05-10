import SwiftUI

struct LibraryTVRecommendedView: View {
    @Environment(MediaFocusModel.self) private var focusModel
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.preferredLandscapeArtworkKind) private var preferredLandscapeArtworkKind

    @State var viewModel: LibraryRecommendedViewModel
    @Binding var heroMedia: MediaItem?
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var bgImageURL: URL?

    private let landscapeHubIdentifiers: [String] = [
        "inprogress",
    ]

    init(
        viewModel: LibraryRecommendedViewModel,
        heroMedia: Binding<MediaItem?>,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        _heroMedia = heroMedia
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                // Full-bleed backdrop with bottom fade
                if let url = bgImageURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        } else {
                            Color.black
                        }
                    }
                } else {
                    Color.black
                }

                // Gradient: clear at top, dark at bottom
                LinearGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.6), Color.black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Info + carousels pinned to the bottom
                VStack(alignment: .leading, spacing: 0) {
                    if let heroMedia {
                        compactHeroInfo(for: heroMedia)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 16)
                    }

                    recommendedContent
                        .frame(height: proxy.size.height * 0.54)
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .task(id: heroMedia?.id) {
            await loadBgImage()
        }
        .onChange(of: viewModel.hubs.count) { _, _ in
            updateHeroMedia()
        }
        .onChange(of: focusModel.focusedMedia?.id) { _, _ in
            updateHeroMedia()
        }
        .onAppear {
            updateHeroMedia()
            updateInitialFocus()
        }
    }

    // MARK: - Compact hero info panel

    private func compactHeroInfo(for media: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(media.primaryLabel)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)

            if let secondary = media.secondaryLabel,
               media.type != .show {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.80))
                    .lineLimit(1)
            }

            if let summary = media.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
    }

    // MARK: - Background image loading

    private func loadBgImage() async {
        guard let media = heroMedia else { bgImageURL = nil; return }
        let path = media.grandparentArtPath
            ?? media.artPath
            ?? media.grandparentThumbPath
            ?? media.parentThumbPath
            ?? media.thumbPath
        guard let path else { bgImageURL = nil; return }
        do {
            let repo = try ImageRepository(context: plexApiContext)
            bgImageURL = repo.transcodeImageURL(
                path: path,
                width: 1920,
                height: 1080,
                minSize: 1,
                upscale: 1
            )
        } catch {
            bgImageURL = nil
        }
    }

    private var recommendedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ForEach(viewModel.hubs) { hub in
                    if hub.hasItems {
                        MediaHubSection(title: hub.title) {
                            carousel(for: hub)
                        }
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("library.recommended.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 24)
        }
    }

    @ViewBuilder
    private func carousel(for hub: Hub) -> some View {
        if shouldUseLandscape(for: hub) {
            MediaCarousel(
                layout: .landscape,
                items: hub.items,
                showsLabels: false,
                onSelectMedia: onSelectMedia,
            )
        } else {
            MediaCarousel(
                layout: .portrait,
                items: hub.items,
                showsLabels: false,
                onSelectMedia: onSelectMedia,
            )
        }
    }

    private func shouldUseLandscape(for hub: Hub) -> Bool {
        if preferredLandscapeArtworkKind != nil {
            return true
        }
        let identifier = hub.id.lowercased()
        return landscapeHubIdentifiers.contains { identifier.contains($0) }
    }

    private var defaultHeroMedia: MediaItem? {
        for hub in viewModel.hubs where hub.hasItems {
            if let item = hub.items.compactMap(\.playableItem).first {
                return item
            }
        }

        return nil
    }

    private func updateHeroMedia() {
        if let focused = focusModel.focusedMedia {
            if heroMedia?.id != focused.id {
                heroMedia = focused
            }
            return
        }

        if heroMedia == nil {
            heroMedia = defaultHeroMedia
        }
    }

    private func updateInitialFocus() {
        guard focusModel.focusedMedia == nil else { return }
        if let initial = heroMedia ?? defaultHeroMedia {
            focusModel.focusedMedia = initial
        }
    }
}
