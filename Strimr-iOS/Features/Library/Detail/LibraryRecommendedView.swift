import SwiftUI

struct LibraryRecommendedView: View {
    @State var viewModel: LibraryRecommendedViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    /// When set, overrides the per-hub landscape-identifier logic and forces
    /// every carousel to use the specified layout. Useful when the consuming
    /// view already knows the library's content type (e.g. "other videos"
    /// libraries that should always show letterbox thumbnails).
    var overrideLayout: MediaCarousel.Layout? = nil

    private let landscapeHubIdentifiers: [String] = [
        "inprogress",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func carousel(for hub: Hub) -> some View {
        if shouldUseLandscape(for: hub) {
            MediaCarousel(
                layout: .landscape,
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia,
            )
        } else {
            MediaCarousel(
                layout: .portrait,
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia,
            )
        }
    }

    private func shouldUseLandscape(for hub: Hub) -> Bool {
        if let override = overrideLayout { return override == .landscape }
        let identifier = hub.id.lowercased()
        return landscapeHubIdentifiers.contains { identifier.contains($0) }
    }
}
